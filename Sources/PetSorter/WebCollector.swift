import Foundation
import UniformTypeIdentifiers

/// 网页投递解析或下载阶段可能返回的用户可读错误。
enum WebCollectorError: LocalizedError {
    case invalidLink
    case unsupportedAddress
    case downloadFailed

    /// 将内部错误映射为桌宠气泡使用的中文说明。
    var errorDescription: String? {
        switch self {
        case .invalidLink: return "投递链接不完整"
        case .unsupportedAddress: return "只支持 http 或 https 网页"
        case .downloadFailed: return "网页素材下载失败"
        }
    }
}

@MainActor
/// 解析浏览器扩展深链，把网页书签或远程媒体交给本地整理引擎。
enum WebCollector {
    /// 校验 `erye://collect` 参数，在临时目录生成文件并自动分类。
    static func collect(
        deepLink: URL,
        settings: SettingsStore,
        history: OperationHistoryStore
    ) async throws -> SortResult {
        guard deepLink.scheme == "erye", deepLink.host == "collect",
              let components = URLComponents(url: deepLink, resolvingAgainstBaseURL: false),
              let targetValue = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let target = URL(string: targetValue) else {
            throw WebCollectorError.invalidLink
        }
        // 只允许网络 URL，拒绝 file、javascript 等可访问本机资源的协议。
        guard ["http", "https"].contains(target.scheme?.lowercased() ?? "") else {
            throw WebCollectorError.unsupportedAddress
        }

        let kind = components.queryItems?.first(where: { $0.name == "kind" })?.value ?? "page"
        let title = components.queryItems?.first(where: { $0.name == "title" })?.value ?? ""
        // 每次投递使用独立临时目录，结束时无论成功失败都清理。
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("erye-web-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }

        // 图片与音视频下载实体文件，普通页面和链接保存为 webloc 书签。
        let stagedFile: URL
        if ["image", "media"].contains(kind) {
            stagedFile = try await download(target, title: title, into: stagingDirectory)
        } else {
            stagedFile = try makeWebloc(target, title: title, in: stagingDirectory)
        }

        let result = FileOrganizer.organize([stagedFile], settings: settings)
        history.record(result, source: "网页投递", discardsOnUndo: true)
        return result
    }

    /// 下载远程媒体，并根据响应文件名或 MIME 类型补全安全文件名。
    private static func download(_ target: URL, title: String, into directory: URL) async throws -> URL {
        let (temporaryURL, response) = try await URLSession.shared.download(from: target)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WebCollectorError.downloadFailed
        }

        var candidate = response.suggestedFilename ?? target.lastPathComponent
        if candidate.isEmpty || candidate == "/" { candidate = cleanFileName(title, fallback: "网页素材") }
        if URL(fileURLWithPath: candidate).pathExtension.isEmpty,
           let mime = response.mimeType,
           let ext = UTType(mimeType: mime)?.preferredFilenameExtension {
            candidate += ".\(ext)"
        }
        candidate = cleanFileName(candidate, fallback: "网页素材")
        let destination = directory.appendingPathComponent(candidate)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    /// 生成 macOS 可双击打开的 XML `.webloc` 文件。
    private static func makeWebloc(_ target: URL, title: String, in directory: URL) throws -> URL {
        let rawName = title.isEmpty ? (target.host ?? "网页收藏") : title
        let name = cleanFileName(rawName, fallback: "网页收藏") + ".webloc"
        let destination = directory.appendingPathComponent(name)
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["URL": target.absoluteString],
            format: .xml,
            options: 0
        )
        try data.write(to: destination, options: .atomic)
        return destination
    }

    /// 替换文件系统保留字符，并把过长网页标题限制在 120 个字符内。
    private static func cleanFileName(_ value: String, fallback: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? fallback : cleaned).prefix(120))
    }
}
