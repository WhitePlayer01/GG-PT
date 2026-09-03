import Foundation
import CryptoKit

/// 描述一次文件移动，供历史记录、今日战报和撤回操作共同使用。
struct FileMoveRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let originalPath: String?
    let destinationPath: String
    let categoryName: String

    /// 创建一条可以恢复到原路径的普通文件移动记录。
    init(originalPath: String, destinationPath: String, categoryName: String) {
        id = UUID()
        self.originalPath = originalPath
        self.destinationPath = destinationPath
        self.categoryName = categoryName
    }

    /// 创建一条网页导入记录；撤回时删除导入副本，而不是恢复到临时目录。
    init(importedDestinationPath: String, categoryName: String) {
        id = UUID()
        originalPath = nil
        destinationPath = importedDestinationPath
        self.categoryName = categoryName
    }

    /// 返回用户可读的目标文件名。
    var fileName: String { URL(fileURLWithPath: destinationPath).lastPathComponent }
}

/// 汇总一批整理任务的成功、失败和重复检测结果。
struct SortResult {
    let movedItems: [FileMoveRecord]
    let failures: [String]
    let duplicateFiles: [String]
    let duplicateBytes: Int64

    var movedCount: Int { movedItems.count }
    var duplicateCount: Int { duplicateFiles.count }
    var categoryNames: [String] { Array(Set(movedItems.map(\.categoryName))).sorted() }
}

/// 描述单个文件在当前设置下会命中的规则和最终去向。
struct SortPreview {
    let matchedRuleName: String?
    let categoryName: String
    let destinationPath: String
    let preferredName: String
}

/// 汇总一次撤回操作已经恢复和未能恢复的文件。
struct UndoResult {
    let restoredItemIDs: Set<UUID>
    let failures: [String]

    var restoredCount: Int { restoredItemIDs.count }
}

@MainActor
/// 执行规则匹配、分类、查重、命名、移动和撤回的核心整理引擎。
enum FileOrganizer {
    /// 按当前设置整理一批文件，并为每个成功移动的文件生成可撤回记录。
    static func organize(
        _ urls: [URL],
        settings: SettingsStore,
        forcedDestinationFolder: String? = nil
    ) -> SortResult {
        let manager = FileManager.default
        let base = URL(fileURLWithPath: settings.baseDirectory, isDirectory: true)
        var movedItems: [FileMoveRecord] = []
        var failures: [String] = []
        var duplicateFiles: [String] = []
        var duplicateBytes: Int64 = 0
        // 同一批文件统一进入本次整理月份的单层年月目录。
        let monthFolderName = settings.organizeByMonthFolder ? currentMonthFolderName() : nil

        for source in urls {
            // 自定义军令优先于内置八分类，首个命中的规则立即生效。
            let category = category(for: source, manager: manager)
            let rule = matchingRule(for: source, rules: settings.sortingRules, manager: manager)
            let requestedFolder = forcedDestinationFolder?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let folderName = requestedFolder.isEmpty
                ? (rule.map { safeRelativeFolder($0.destinationFolder) } ?? settings.subfolder(for: category))
                : safeRelativeFolder(requestedFolder)
            var destinationFolder = base.appendingPathComponent(folderName, isDirectory: true)
            if let monthFolderName {
                destinationFolder.appendPathComponent(monthFolderName, isDirectory: true)
            }

            do {
                try manager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                if settings.detectDuplicates,
                   let size = try duplicateSizeIfFound(source, in: destinationFolder, manager: manager) {
                    // 重复文件保持在原位置，只把结果写进战报。
                    duplicateFiles.append(source.lastPathComponent)
                    duplicateBytes += size
                    continue
                }
                // 先生成智能名称，再通过自动编号解决同名冲突。
                let destination = availableDestination(
                    in: destinationFolder,
                    preferredName: preferredName(for: source, category: category, settings: settings),
                    manager: manager
                )
                try manager.moveItem(at: source, to: destination)
                movedItems.append(
                    FileMoveRecord(
                        originalPath: source.path,
                        destinationPath: destination.path,
                        categoryName: rule?.name ?? category.rawValue
                    )
                )
            } catch {
                failures.append("\(source.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        return SortResult(
            movedItems: movedItems,
            failures: failures,
            duplicateFiles: duplicateFiles,
            duplicateBytes: duplicateBytes
        )
    }

    /// 只计算规则命中、智能名称和目标目录，不移动所选文件。
    static func preview(_ source: URL, settings: SettingsStore) -> SortPreview {
        let manager = FileManager.default
        let category = category(for: source, manager: manager)
        let rule = matchingRule(for: source, rules: settings.sortingRules, manager: manager)
        let folderName = rule.map { safeRelativeFolder($0.destinationFolder) } ?? settings.subfolder(for: category)
        var destination = URL(fileURLWithPath: settings.baseDirectory, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        if settings.organizeByMonthFolder {
            destination.appendPathComponent(currentMonthFolderName(), isDirectory: true)
        }
        return SortPreview(
            matchedRuleName: rule?.name,
            categoryName: category.rawValue,
            destinationPath: destination.path,
            preferredName: preferredName(for: source, category: category, settings: settings)
        )
    }

    /// 按移动记录的逆序恢复文件，避免父子路径操作互相影响。
    static func undo(_ items: [FileMoveRecord]) -> UndoResult {
        let manager = FileManager.default
        var restoredItemIDs = Set<UUID>()
        var failures: [String] = []

        for item in items.reversed() {
            let current = URL(fileURLWithPath: item.destinationPath)
            guard manager.fileExists(atPath: current.path) else {
                failures.append("\(item.fileName)：收纳后的文件已不存在")
                continue
            }

            do {
                guard let originalPath = item.originalPath else {
                    // 网页投递没有有意义的原路径，撤回语义就是删除下载副本。
                    try manager.removeItem(at: current)
                    restoredItemIDs.insert(item.id)
                    continue
                }
                let original = URL(fileURLWithPath: originalPath)
                guard !manager.fileExists(atPath: original.path) else {
                    // 永不覆盖用户后来放回原位置的同名文件。
                    failures.append("\(item.fileName)：原位置已有同名文件")
                    continue
                }
                try manager.createDirectory(
                    at: original.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try manager.moveItem(at: current, to: original)
                restoredItemIDs.insert(item.id)
            } catch {
                failures.append("\(item.fileName)：\(error.localizedDescription)")
            }
        }

        return UndoResult(restoredItemIDs: restoredItemIDs, failures: failures)
    }

    /// 根据目录属性或扩展名返回内置文件分类。
    static func category(for url: URL, manager: FileManager = .default) -> FileCategory {
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return .folders
        }
        let ext = url.pathExtension.lowercased()
        return FileCategory.allCases.first(where: { $0.extensions.contains(ext) }) ?? .other
    }

    /// 按数组顺序寻找首个同时满足全部已填写条件的启用规则。
    private static func matchingRule(
        for url: URL,
        rules: [SortingRule],
        manager: FileManager
    ) -> SortingRule? {
        var isDirectory: ObjCBool = false
        let directory = manager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        let attributes = try? manager.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.doubleValue ?? 0
        let name = url.lastPathComponent.lowercased()
        let sourcePath = url.deletingLastPathComponent().path.lowercased()
        let ext = url.pathExtension.lowercased()
        let createdAt = (try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]))
            .flatMap { $0.creationDate ?? $0.contentModificationDate } ?? Date()

        return rules.first { rule in
            guard rule.isEnabled, rule.hasCondition,
                  !rule.destinationFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

            let keyword = rule.fileNameContains.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !keyword.isEmpty, !name.contains(keyword) { return false }

            let sourceKeyword = rule.sourcePathContains.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !sourceKeyword.isEmpty {
                // 由系统位置选择器写入的绝对路径按目录边界匹配；手输关键词仍兼容模糊匹配。
                if sourceKeyword.hasPrefix("/") {
                    if sourcePath != sourceKeyword && !sourcePath.hasPrefix(sourceKeyword + "/") { return false }
                } else if !sourcePath.contains(sourceKeyword) {
                    return false
                }
            }

            let extensions = Set(
                // 同时兼容中英文逗号、空格以及带点后缀写法。
                rule.extensions
                    .lowercased()
                    .split(whereSeparator: { $0 == "," || $0 == "，" || $0.isWhitespace })
                    .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
                    .filter { !$0.isEmpty }
            )
            if !extensions.isEmpty, directory || !extensions.contains(ext) { return false }

            let megabytes = size / 1_048_576
            if rule.minimumSizeMB > 0, megabytes < rule.minimumSizeMB { return false }
            if rule.maximumSizeMB > 0, megabytes > rule.maximumSizeMB { return false }
            let ageDays = max(0, Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0)
            if rule.createdWithinDays > 0, ageDays > rule.createdWithinDays { return false }
            if rule.olderThanDays > 0, ageDays < rule.olderThanDays { return false }
            return true
        }
    }

    /// 清理规则中的相对路径，阻止 `.` 和 `..` 逃逸总收纳目录。
    private static func safeRelativeFolder(_ value: String) -> String {
        let parts = value
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        return parts.isEmpty ? "自定义" : parts.joined(separator: "/")
    }

    /// 以本机当前年月生成一个单层目录名，例如 `2026-08`。
    private static func currentMonthFolderName() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    /// 先比较文件大小，再用 SHA-256 判断目标目录中是否存在内容相同文件。
    private static func duplicateSizeIfFound(_ source: URL, in folder: URL, manager: FileManager) throws -> Int64? {
        let sourceValues = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard sourceValues.isRegularFile == true, let sourceSize = sourceValues.fileSize else { return nil }
        let candidates = try manager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        let sameSize = try candidates.filter { candidate in
            let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            return values.isRegularFile == true && values.fileSize == sourceSize
        }
        // 只有存在同尺寸候选时才计算哈希，减少大目录中的无效读取。
        guard !sameSize.isEmpty else { return nil }
        let sourceHash = try sha256(of: source)
        for candidate in sameSize where try sha256(of: candidate) == sourceHash {
            return Int64(sourceSize)
        }
        return nil
    }

    /// 以 1 MB 数据块流式计算文件 SHA-256，避免一次载入整个大文件。
    private static func sha256(of url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize()
    }

    /// 根据用户选择的命名方案组合日期、来源、分类和原文件名。
    private static func preferredName(
        for source: URL,
        category: FileCategory,
        settings: SettingsStore
    ) -> String {
        guard settings.smartNamingStyle != .original else { return source.lastPathComponent }
        var isDirectory: ObjCBool = false
        // 文件夹始终保留原名，避免重命名整个目录造成意外影响。
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return source.lastPathComponent }

        let values = try? source.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        let date = values?.contentModificationDate ?? values?.creationDate ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateText = formatter.string(from: date)
        let parent = source.deletingLastPathComponent().lastPathComponent
        let sourceText = parent.hasPrefix("erye-web-") ? "网页" : cleanNameComponent(parent)
        let original = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        let stem: String
        switch settings.smartNamingStyle {
        case .original: stem = original
        case .dateOriginal: stem = "\(dateText)-\(original)"
        case .sourceDateOriginal: stem = "\(sourceText)-\(dateText)-\(original)"
        case .typeDateOriginal: stem = "\(category.rawValue)-\(dateText)-\(original)"
        }
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    /// 移除不能安全出现在 macOS 文件名组成部分中的字符。
    private static func cleanNameComponent(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? "本机" : cleaned).prefix(40))
    }

    /// 在不覆盖已有文件的前提下返回可用目标路径，并追加递增编号。
    private static func availableDestination(in folder: URL, preferredName: String, manager: FileManager) -> URL {
        let original = folder.appendingPathComponent(preferredName)
        guard manager.fileExists(atPath: original.path) else { return original }

        let source = URL(fileURLWithPath: preferredName)
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var number = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem)-\(number)" : "\(stem)-\(number).\(ext)"
            let candidate = folder.appendingPathComponent(candidateName)
            if !manager.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }
}
