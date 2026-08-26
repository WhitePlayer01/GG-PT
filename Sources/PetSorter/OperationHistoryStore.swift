import Foundation

/// 表示一次拖放、网页投递或自动巡查产生的完整操作记录。
struct SortOperation: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let source: String
    var items: [FileMoveRecord]
    let duplicateCount: Int
    let duplicateBytes: Int64
    let failureCount: Int

    /// 创建新的操作记录及其重复、失败统计。
    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        source: String,
        items: [FileMoveRecord],
        duplicateCount: Int,
        duplicateBytes: Int64,
        failureCount: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.items = items
        self.duplicateCount = duplicateCount
        self.duplicateBytes = duplicateBytes
        self.failureCount = failureCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, source, items, duplicateCount, duplicateBytes, failureCount
    }

    /// 解码历史记录，并为旧版本缺失的统计字段提供零值。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        source = try values.decode(String.self, forKey: .source)
        items = try values.decode([FileMoveRecord].self, forKey: .items)
        duplicateCount = try values.decodeIfPresent(Int.self, forKey: .duplicateCount) ?? 0
        duplicateBytes = try values.decodeIfPresent(Int64.self, forKey: .duplicateBytes) ?? 0
        failureCount = try values.decodeIfPresent(Int.self, forKey: .failureCount) ?? 0
    }
}

/// 聚合当天的操作次数、移动数、重复空间和分类分布。
struct DailySortSummary {
    let operationCount: Int
    let movedCount: Int
    let duplicateCount: Int
    let savedBytes: Int64
    let failureCount: Int
    let categoryCounts: [(name: String, count: Int)]
}

@MainActor
/// 持久化最近 100 次整理操作，并提供今日战报和一键撤回能力。
final class OperationHistoryStore: ObservableObject {
    @Published private(set) var operations: [SortOperation] = []

    private let historyURL: URL

    /// 确定历史文件位置并加载已有记录。
    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // 沿用旧版数据目录名称，确保升级为“云长卫”后仍能读取撤回历史。
        let directory = support.appendingPathComponent("二爷收着", isDirectory: true)
        historyURL = directory.appendingPathComponent("history.json")
        load()
    }

    /// 返回最新一次操作，不保证其中一定有可撤回文件。
    var lastOperation: SortOperation? { operations.first }
    /// 判断历史中是否存在至少一条可以恢复或删除的移动记录。
    var canUndo: Bool { operations.contains(where: { !$0.items.isEmpty }) }

    /// 根据系统日历即时计算今日战报。
    var todaySummary: DailySortSummary {
        let calendar = Calendar.current
        let today = operations.filter { calendar.isDateInToday($0.createdAt) }
        var categories: [String: Int] = [:]
        for item in today.flatMap(\.items) { categories[item.categoryName, default: 0] += 1 }
        return DailySortSummary(
            operationCount: today.count,
            movedCount: today.reduce(0) { $0 + $1.items.count },
            duplicateCount: today.reduce(0) { $0 + $1.duplicateCount },
            savedBytes: today.reduce(0) { $0 + $1.duplicateBytes },
            failureCount: today.reduce(0) { $0 + $1.failureCount },
            categoryCounts: categories.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
        )
    }

    /// 记录一次整理结果；纯失败或纯重复任务同样会进入战报。
    func record(_ result: SortResult, source: String, discardsOnUndo: Bool = false) {
        guard !result.movedItems.isEmpty || result.duplicateCount > 0 || !result.failures.isEmpty else { return }
        // 网页投递的源文件位于临时目录，转换为“撤回即删除”的导入记录。
        let items = discardsOnUndo
            ? result.movedItems.map {
                FileMoveRecord(importedDestinationPath: $0.destinationPath, categoryName: $0.categoryName)
            }
            : result.movedItems
        operations.insert(
            SortOperation(
                source: source,
                items: items,
                duplicateCount: result.duplicateCount,
                duplicateBytes: result.duplicateBytes,
                failureCount: result.failures.count
            ),
            at: 0
        )
        operations = Array(operations.prefix(100))
        save()
    }

    @discardableResult
    /// 撤回最近一条含文件移动的操作，并保留其中未能恢复的项目。
    func undoLast() -> UndoResult? {
        guard let index = operations.firstIndex(where: { !$0.items.isEmpty }) else { return nil }
        let operation = operations[index]
        let result = FileOrganizer.undo(operation.items)
        let remaining = operation.items.filter { !result.restoredItemIDs.contains($0.id) }

        if remaining.isEmpty {
            operations.remove(at: index)
        } else {
            operations[index].items = remaining
        }
        save()
        return result
    }

    /// 从 Application Support 中读取历史 JSON；文件不存在或损坏时使用空历史。
    private func load() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([SortOperation].self, from: data) else { return }
        operations = decoded
    }

    /// 原子写入历史 JSON，避免应用中断导致半份记录。
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
/// 在应用各服务和桌宠界面之间传递一次性状态消息。
final class PetEventStore: ObservableObject {
    @Published private(set) var sequence = 0
    private(set) var message = ""

    /// 发布新消息并递增序号，确保相同文字也能再次触发界面更新。
    func announce(_ message: String) {
        self.message = message
        sequence += 1
    }
}
