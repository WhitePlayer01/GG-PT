import Foundation
import AppKit

/// 对应 GitHub Releases API 返回的一条发布记录。
struct AppRelease: Decodable, Equatable {
    /// 对应发布记录中的单个可下载附件。
    struct Asset: Decodable, Equatable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, assets
        case htmlURL = "html_url"
    }

    /// 去除版本标签前常见的 `v` 前缀。
    var version: String { tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")) }
    /// 优先使用发布标题，没有标题时回退为版本号。
    var displayName: String { name?.isEmpty == false ? name! : "版本 \(version)" }
    /// 优先选择 DMG、PKG 或 ZIP 附件，否则打开 GitHub 发布页。
    var preferredDownloadURL: URL {
        let extensions = [".dmg", ".pkg", ".zip"]
        return assets.first(where: { asset in
            extensions.contains(where: { asset.name.lowercased().hasSuffix($0) })
        })?.browserDownloadURL ?? htmlURL
    }
}

@MainActor
/// 查询 GitHub 最新版本并向设置页发布检查状态。
final class UpdateService: ObservableObject {
    /// 描述一次更新检查的完整状态机。
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case failed(String)
        case updateAvailable(AppRelease)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var availableRelease: AppRelease?

    /// 从应用 Info.plist 获取当前展示版本。
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    /// 从应用 Info.plist 获取内部构建号，便于区分同一版本的不同安装包。
    static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "本地"
    }

    private let latestReleaseURL = URL(string: "https://api.github.com/repos/WhitePlayer01/GG-PT/releases/latest")!

    /// 请求最新 GitHub Release，并比较远端与本地版本号。
    func check(silently: Bool = false) {
        guard status != .checking else { return }
        status = .checking

        Task {
            do {
                // GitHub API 要求明确的媒体类型和可识别 User-Agent。
                var request = URLRequest(url: latestReleaseURL)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("PetSorter/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let release = try JSONDecoder().decode(AppRelease.self, from: data)
                if Self.isNewer(release.version, than: Self.currentVersion) {
                    availableRelease = release
                    status = .updateAvailable(release)
                } else {
                    availableRelease = nil
                    status = .upToDate
                }
            } catch {
                if silently {
                    status = .idle
                } else {
                    status = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// 使用系统默认浏览器打开首选安装包或发布页面。
    func openDownload(for release: AppRelease? = nil) {
        guard let release = release ?? availableRelease else { return }
        NSWorkspace.shared.open(release.preferredDownloadURL)
    }

    /// 使用数字比较规则判断候选版本是否高于当前版本。
    private static func isNewer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }
}
