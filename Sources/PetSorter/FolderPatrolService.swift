import Foundation
import Combine

/// 汇总巡查目录中需要用户手动确认的清理建议。
struct CleanupSuggestion: Equatable {
    var emptyFolderCount = 0
    var oldInstallerCount = 0
    var oldArchiveCount = 0

    /// 表示当前没有任何清理提醒。
    var isEmpty: Bool { emptyFolderCount == 0 && oldInstallerCount == 0 && oldArchiveCount == 0 }
}

@MainActor
/// 定时扫描桌面和下载目录，并把符合条件的文件交给整理引擎。
final class FolderPatrolService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var cleanupSuggestion = CleanupSuggestion()

    private let settings: SettingsStore
    private let history: OperationHistoryStore
    private let events: PetEventStore
    private var timer: Timer?
    private var settingsCancellable: AnyCancellable?

    /// 注入共享设置、历史和桌宠消息通道。
    init(settings: SettingsStore, history: OperationHistoryStore, events: PetEventStore) {
        self.settings = settings
        self.history = history
        self.events = events
    }

    /// 监听巡查开关和间隔变化，并启动或重建定时器。
    func start() {
        settingsCancellable = settings.$monitorDesktop
            .combineLatest(settings.$monitorDownloads, settings.$monitorIntervalMinutes)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.reschedule() }
            }
        reschedule()
    }

    /// 立即执行一次巡查，并根据整理结果更新战报和桌宠提示。
    func patrolNow(announcesEmpty: Bool = true) {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        // 先写入巡查时间，即使没有候选文件也能告诉用户功能正常运行。
        let candidates = patrolCandidates()
        settings.lastPatrolDate = Date()
        guard !candidates.isEmpty else {
            if announcesEmpty { events.announce("巡查完毕，没有待收文件", outcome: .neutral) }
            return
        }

        let result = FileOrganizer.organize(candidates, settings: settings)
        history.record(result, source: "自动巡查")
        if result.movedCount > 0 {
            var message = "巡查收了 \(result.movedCount) 件"
            if result.duplicateCount > 0 { message += "，拦下 \(result.duplicateCount) 件重复" }
            events.announce(
                message,
                outcome: .complete,
                category: FileCategory(rawValue: result.categoryNames.first ?? "")
            )
        } else if result.duplicateCount > 0 {
            events.announce("巡查发现 \(result.duplicateCount) 件重复文件，已留在原处", outcome: .complete)
        } else if let failure = result.failures.first {
            events.announce("巡查未完成：\(failure)", outcome: .failure)
        }
    }

    /// 根据当前开关重建重复定时器；没有开启目录时不保留空转定时器。
    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard settings.monitorDesktop || settings.monitorDownloads else { return }
        let interval = TimeInterval(max(settings.monitorIntervalMinutes, 5) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.patrolNow(announcesEmpty: false) }
        }
    }

    /// 返回本次允许自动移动的安全候选文件列表。
    private func patrolCandidates() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var folders: [URL] = []
        if settings.monitorDesktop { folders.append(home.appendingPathComponent("Desktop", isDirectory: true)) }
        if settings.monitorDownloads { folders.append(home.appendingPathComponent("Downloads", isDirectory: true)) }
        refreshCleanupSuggestions(in: folders)

        let basePath = URL(fileURLWithPath: settings.baseDirectory).standardizedFileURL.path
        let keys: Set<URLResourceKey> = [.isHiddenKey, .isDirectoryKey, .contentModificationDateKey]
        // 清理建议中的旧安装包和压缩包只提醒，不参与自动移动。
        let cleanupExtensions: Set<String> = ["dmg", "pkg", "zip", "rar", "7z", "tar", "gz", "bz2"]
        let cleanupCutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return folders.flatMap { folder in
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )) ?? []
            return contents.filter { url in
                let path = url.standardizedFileURL.path
                // 跳过收纳箱自身以及包含收纳箱的上级候选目录。
                if path == basePath || basePath.hasPrefix(path + "/") { return false }
                // 浏览器尚未完成的下载文件不能提前整理。
                if ["download", "crdownload", "part"].contains(url.pathExtension.lowercased()) { return false }
                let values = try? url.resourceValues(forKeys: keys)
                if values?.isHidden == true { return false }
                if values?.isDirectory == true { return false }
                // 给正在写入的文件保留一分钟稳定时间。
                if let modified = values?.contentModificationDate,
                   Date().timeIntervalSince(modified) < 60 { return false }
                if let modified = values?.contentModificationDate,
                   modified < cleanupCutoff,
                   cleanupExtensions.contains(url.pathExtension.lowercased()) { return false }
                return true
            }
        }
    }

    /// 扫描空文件夹和 30 天前的安装包、压缩包，只生成提醒而不删除内容。
    private func refreshCleanupSuggestions(in folders: [URL]) {
        var suggestion = CleanupSuggestion()
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let installerExtensions: Set<String> = ["dmg", "pkg"]
        let archiveExtensions: Set<String> = ["zip", "rar", "7z", "tar", "gz", "bz2"]

        for folder in folders {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in contents {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                if values?.isDirectory == true {
                    let children = try? FileManager.default.contentsOfDirectory(atPath: url.path)
                    if children?.isEmpty == true { suggestion.emptyFolderCount += 1 }
                    continue
                }
                guard let modified = values?.contentModificationDate, modified < cutoff else { continue }
                let ext = url.pathExtension.lowercased()
                if installerExtensions.contains(ext) { suggestion.oldInstallerCount += 1 }
                if archiveExtensions.contains(ext) { suggestion.oldArchiveCount += 1 }
            }
        }
        cleanupSuggestion = suggestion
    }
}
