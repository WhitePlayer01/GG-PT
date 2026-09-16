import Foundation
import Combine

/// 汇总巡查目录中需要用户手动确认的清理建议。
struct CleanupSuggestion: Equatable {
    var emptyFolderCount = 0
    var oldInstallerCount = 0
    var oldArchiveCount = 0
    var isEmpty: Bool { emptyFolderCount == 0 && oldInstallerCount == 0 && oldArchiveCount == 0 }
}

/// 保留扫描时文件身份和修改信息，确认时拒绝处理已被替换或写入的文件。
struct PatrolCandidate: Identifiable {
    let url: URL
    let modified: Date
    let size: Int
    let identifier: String
    var id: String { url.path }
    let preview: SortPreview
}

struct PatrolScan {
    var candidates: [PatrolCandidate] = []
    var cleanup = CleanupSuggestion()
    var errors: [String] = []
}

/* 扫描和复核共用安全过滤，始终只读取第一层普通文件。
 文件属性无法读取时跳过；符号链接不跟随，旧安装包仅生成提醒。 */
enum PatrolScanner {
    static func scan(folders: [URL], configuration: SortingConfiguration, now: Date = Date()) -> PatrolScan {
        var result = PatrolScan()
        let manager = FileManager.default
        let cutoff = now.addingTimeInterval(-30 * 86400)
        let installers: Set<String> = ["dmg", "pkg"]
        let archives: Set<String> = ["zip", "rar", "7z", "tar", "gz", "bz2"]
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
            .isHiddenKey, .contentModificationDateKey, .fileSizeKey, .fileResourceIdentifierKey]
        let base = URL(fileURLWithPath: configuration.baseDirectory).resolvingSymlinksInPath().path
        for folder in folders {
            // 收纳箱内部不能再当作输入目录，避免重复整理。
            let root = folder.resolvingSymlinksInPath().path
            if root == base || root.hasPrefix(base + "/") { continue }
            do {
                let urls = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
                for url in urls.sorted(by: { $0.path < $1.path }) {
                    guard let value = try? url.resourceValues(forKeys: keys),
                          value.isSymbolicLink != true, value.isHidden != true else { continue }
                    let path = url.standardizedFileURL.path
                    if path == base || base.hasPrefix(path + "/") { continue }
                    if value.isDirectory == true {
                        if let children = try? manager.contentsOfDirectory(atPath: path), children.isEmpty {
                            result.cleanup.emptyFolderCount += 1
                        }
                        continue
                    }
                    guard value.isRegularFile == true, let modified = value.contentModificationDate,
                          let size = value.fileSize, let identifier = value.fileResourceIdentifier else { continue }
                    let ext = url.pathExtension.lowercased()
                    if modified < cutoff {
                        if installers.contains(ext) { result.cleanup.oldInstallerCount += 1; continue }
                        if archives.contains(ext) { result.cleanup.oldArchiveCount += 1; continue }
                    }
                    guard !["download", "crdownload", "part"].contains(ext), now.timeIntervalSince(modified) >= 60 else { continue }
                    result.candidates.append(PatrolCandidate(url: url, modified: modified, size: size,
                        identifier: String(describing: identifier), preview: FileOrganizer.preview(url, settings: configuration)))
                }
            } catch { result.errors.append("\(folder.lastPathComponent)：\(error.localizedDescription)") }
        }
        return result
    }

    /// 确认后只返回仍符合条件且身份、大小、修改时间一致的选中项。
    static func revalidated(_ selected: [PatrolCandidate], folders: [URL], configuration: SortingConfiguration) -> [URL] {
        let current = Dictionary(uniqueKeysWithValues: scan(folders: folders, configuration: configuration).candidates.map { ($0.id, $0) })
        return selected.compactMap { item in
            guard let fresh = current[item.id], fresh.modified == item.modified,
                  fresh.size == item.size, fresh.identifier == item.identifier else { return nil }
            return item.url
        }
    }
}

@MainActor
/* 主线程只管理状态与反馈；磁盘扫描、查重和文件移动放到后台。
 预览会暂停定时巡查，确认只处理勾选项；关闭预览后恢复原计划。 */
final class FolderPatrolService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isPreviewing = false
    @Published private(set) var previewItems: [PatrolCandidate] = []
    @Published private(set) var previewMessage = ""
    @Published private(set) var cleanupSuggestion = CleanupSuggestion()
    private let settings: SettingsStore
    private let history: OperationHistoryStore
    private let events: PetEventStore
    private let folderProvider: (() -> [URL])?
    private var timer: Timer?
    private var settingsCancellable: AnyCancellable?
    private var previewConfiguration: SortingConfiguration?
    private var previewFolders: [URL] = []
    private var generation = UUID()

    init(settings: SettingsStore, history: OperationHistoryStore, events: PetEventStore,
         folderProvider: (() -> [URL])? = nil) {
        self.settings = settings; self.history = history; self.events = events
        // 测试和原生截图可注入临时目录，正式运行仍由用户的开关决定。
        self.folderProvider = folderProvider
    }

    func start() {
        settingsCancellable = settings.$monitorDesktop
            .combineLatest(settings.$monitorDownloads, settings.$monitorIntervalMinutes)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.reschedule() } }
        reschedule()
    }

    private var folders: [URL] {
        if let folderProvider { return folderProvider() }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [(settings.monitorDesktop, "Desktop"), (settings.monitorDownloads, "Downloads")]
            .filter { $0.0 }.map { home.appendingPathComponent($0.1, isDirectory: true) }
    }

    /// 仅扫描候选项，不创建目录、不查重、不移动文件。
    func preparePreview() {
        guard !isRunning else { return }
        isPreviewing = true; isRunning = true; previewItems = []; previewMessage = "正在读取待整理文件…"
        let configuration = SortingConfiguration(settings: settings)
        let roots = folders
        previewConfiguration = configuration; previewFolders = roots
        let request = UUID(); generation = request
        Task {
            let scan = await Task.detached(priority: .utility) { PatrolScanner.scan(folders: roots, configuration: configuration) }.value
            guard generation == request else { return }
            isRunning = false; previewItems = scan.candidates; cleanupSuggestion = scan.cleanup
            previewMessage = scan.errors.isEmpty ? "预览期间已暂停定时巡查。取消勾选仅跳过本次。" : scan.errors.joined(separator: "\n")
        }
    }

    func closePreview() {
        // 扫描可在关闭后丢弃结果；实际移动期间界面禁止关闭。
        generation = UUID(); isPreviewing = false; isRunning = false
        previewItems = []; previewConfiguration = nil
    }

    func confirmPreview(selectedIDs: Set<String>) {
        guard isPreviewing, !isRunning, let configuration = previewConfiguration else { return }
        guard configuration == SortingConfiguration(settings: settings), previewFolders == folders else {
            previewMessage = "设置已变化，请刷新预览后再确认。"; return
        }
        let selected = previewItems.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        isRunning = true
        let roots = previewFolders
        events.receivedFiles()
        Task {
            let output = await Task.detached(priority: .utility) {
                let valid = PatrolScanner.revalidated(selected, folders: roots, configuration: configuration)
                return (FileOrganizer.organize(valid, settings: configuration), selected.count - valid.count)
            }.value
            finish(output.0, announcesEmpty: true)
            previewItems = []; previewConfiguration = nil
            previewMessage = "已收纳 \(output.0.movedCount) 件，重复 \(output.0.duplicateCount) 件，失败 \(output.0.failures.count) 件；变化或不可用跳过 \(output.1) 件。关闭后恢复定时巡查。"
        }
    }

    func patrolNow(announcesEmpty: Bool = true) {
        guard !isRunning, !isPreviewing else { return }
        isRunning = true
        let configuration = SortingConfiguration(settings: settings)
        let roots = folders
        Task {
            let scan = await Task.detached(priority: .utility) { PatrolScanner.scan(folders: roots, configuration: configuration) }.value
            cleanupSuggestion = scan.cleanup
            if !scan.candidates.isEmpty { events.receivedFiles() }
            let result = await Task.detached(priority: .utility) {
                let valid = PatrolScanner.revalidated(scan.candidates, folders: roots, configuration: configuration)
                return FileOrganizer.organize(valid, settings: configuration)
            }.value
            finish(result, announcesEmpty: announcesEmpty)
            if !scan.errors.isEmpty { events.announce(scan.errors.joined(separator: "；"), outcome: .failure) }
        }
    }

    /// 沿用历史和角色消息通道；失败与重复仍可在记录中查看。
    private func finish(_ result: SortResult, announcesEmpty: Bool) {
        isRunning = false; settings.lastPatrolDate = Date()
        history.record(result, source: "自动巡查")
        if result.movedCount > 0 || result.duplicateCount > 0 || !result.failures.isEmpty {
            events.announce("巡查收了 \(result.movedCount) 件，重复 \(result.duplicateCount) 件，失败 \(result.failures.count) 件",
                outcome: result.failures.isEmpty ? .complete : .failure,
                category: FileCategory(rawValue: result.categoryNames.first ?? ""))
        } else if announcesEmpty { events.announce("巡查完毕，没有待收文件", outcome: .neutral) }
    }

    private func reschedule() {
        timer?.invalidate(); timer = nil
        guard settings.monitorDesktop || settings.monitorDownloads else { return }
        let interval = TimeInterval(max(settings.monitorIntervalMinutes, 5) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.patrolNow(announcesEmpty: false) }
        }
        timer?.tolerance = min(60, interval * 0.1)
    }
}
