import Foundation

struct SortOperation: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let source: String
    var items: [FileMoveRecord]
}

@MainActor
final class OperationHistoryStore: ObservableObject {
    @Published private(set) var operations: [SortOperation] = []

    private let historyURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("二爷收着", isDirectory: true)
        historyURL = directory.appendingPathComponent("history.json")
        load()
    }

    var lastOperation: SortOperation? { operations.first }
    var canUndo: Bool { lastOperation != nil }

    func record(_ result: SortResult, source: String, discardsOnUndo: Bool = false) {
        guard !result.movedItems.isEmpty else { return }
        let items = discardsOnUndo
            ? result.movedItems.map {
                FileMoveRecord(importedDestinationPath: $0.destinationPath, categoryName: $0.categoryName)
            }
            : result.movedItems
        operations.insert(
            SortOperation(id: UUID(), createdAt: Date(), source: source, items: items),
            at: 0
        )
        operations = Array(operations.prefix(100))
        save()
    }

    @discardableResult
    func undoLast() -> UndoResult? {
        guard let operation = operations.first else { return nil }
        let result = FileOrganizer.undo(operation.items)
        let remaining = operation.items.filter { !result.restoredItemIDs.contains($0.id) }

        if remaining.isEmpty {
            operations.removeFirst()
        } else {
            operations[0].items = remaining
        }
        save()
        return result
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([SortOperation].self, from: data) else { return }
        operations = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: historyURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(operations).write(to: historyURL, options: .atomic)
        } catch {
            NSLog("保存收纳历史失败：%@", error.localizedDescription)
        }
    }
}

@MainActor
final class PetEventStore: ObservableObject {
    @Published private(set) var sequence = 0
    private(set) var message = ""

    func announce(_ message: String) {
        self.message = message
        sequence += 1
    }
}
