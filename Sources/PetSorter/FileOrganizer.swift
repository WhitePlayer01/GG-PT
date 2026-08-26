import Foundation

struct FileMoveRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let originalPath: String?
    let destinationPath: String
    let categoryName: String

    init(originalPath: String, destinationPath: String, categoryName: String) {
        id = UUID()
        self.originalPath = originalPath
        self.destinationPath = destinationPath
        self.categoryName = categoryName
    }

    init(importedDestinationPath: String, categoryName: String) {
        id = UUID()
        originalPath = nil
        destinationPath = importedDestinationPath
        self.categoryName = categoryName
    }

    var fileName: String { URL(fileURLWithPath: destinationPath).lastPathComponent }
}

struct SortResult {
    let movedItems: [FileMoveRecord]
    let failures: [String]

    var movedCount: Int { movedItems.count }
    var categoryNames: [String] { Array(Set(movedItems.map(\.categoryName))).sorted() }
}

struct UndoResult {
    let restoredItemIDs: Set<UUID>
    let failures: [String]

    var restoredCount: Int { restoredItemIDs.count }
}

@MainActor
enum FileOrganizer {
    static func organize(_ urls: [URL], settings: SettingsStore) -> SortResult {
        let manager = FileManager.default
        let base = URL(fileURLWithPath: settings.baseDirectory, isDirectory: true)
        var moved = 0
        var movedItems: [FileMoveRecord] = []
        var failures: [String] = []

        for source in urls {
            let category = category(for: source, manager: manager)
            let folderName = settings.subfolder(for: category)
            let destinationFolder = base.appendingPathComponent(folderName, isDirectory: true)

            do {
                try manager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                let destination = availableDestination(
                    in: destinationFolder,
                    preferredName: source.lastPathComponent,
                    manager: manager
                )
                try manager.moveItem(at: source, to: destination)
                moved += 1
                movedItems.append(
                    FileMoveRecord(
                        originalPath: source.path,
                        destinationPath: destination.path,
                        categoryName: category.rawValue
                    )
                )
            } catch {
                failures.append("\(source.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        return SortResult(movedItems: movedItems, failures: failures)
    }

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
                    try manager.removeItem(at: current)
                    restoredItemIDs.insert(item.id)
                    continue
                }
                let original = URL(fileURLWithPath: originalPath)
                guard !manager.fileExists(atPath: original.path) else {
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

    private static func category(for url: URL, manager: FileManager) -> FileCategory {
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return .folders
        }
        let ext = url.pathExtension.lowercased()
        return FileCategory.allCases.first(where: { $0.extensions.contains(ext) }) ?? .other
    }

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
