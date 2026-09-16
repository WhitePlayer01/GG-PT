import Foundation
import AppKit

/* 临时文件覆盖筛选、军令匹配、预览不写盘、变化复核和撤回冲突。
 内存偏好与独立历史路径确保测试不触碰用户的目录和收纳记录。 */
@main struct OrganizationTests {
    @MainActor static func main() async throws {
        let manager = FileManager.default
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("sort-tests-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let input = root.appendingPathComponent("input")
        try manager.createDirectory(at: input, withIntermediateDirectories: true)
        let settings = SettingsStore(defaults: OrganizationTestDefaults())
        settings.baseDirectory = root.appendingPathComponent("sorted").path
        settings.organizeByMonthFolder = false
        settings.smartNamingStyle = .original
        let old = Date().addingTimeInterval(-120)
        func file(_ name: String, date: Date = old) throws -> URL {
            let url = input.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            try manager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            return url
        }
        let screenshot = try file("截图-样例.png")
        let course = try file("课程讲义.pdf")
        let project = try file("项目计划.docx")
        _ = try file("recent.txt", date: Date())
        _ = try file("partial.crdownload")
        _ = try file(".hidden.txt")
        _ = try file("old.zip", date: Date().addingTimeInterval(-31 * 86400))
        try manager.createSymbolicLink(at: input.appendingPathComponent("link.pdf"), withDestinationURL: course)
        try manager.createDirectory(at: input.appendingPathComponent("empty"), withIntermediateDirectories: true)
        for (template, url) in zip(SortingRuleTemplate.allCases, [screenshot, course, project]) {
            var rule = template.makeRule()
            precondition(!rule.isEnabled)
            settings.sortingRules = [rule]
            precondition(FileOrganizer.preview(url, settings: settings).matchedRuleName == nil)
            rule.isEnabled = true; settings.sortingRules = [rule]
            precondition(FileOrganizer.preview(url, settings: settings).matchedRuleName == rule.name)
            precondition(template.makeRule().id != rule.id)
        }
        settings.sortingRules = []
        let config = SortingConfiguration(settings: settings)
        let scan = PatrolScanner.scan(folders: [input], configuration: config)
        precondition(Set(scan.candidates.map { $0.url.path }) == Set([screenshot.path, course.path, project.path]), "候选项：\(scan.candidates.map { $0.url.path })；期待：\([screenshot.path, course.path, project.path])；错误：\(scan.errors)")
        precondition(scan.cleanup.oldArchiveCount == 1 && scan.cleanup.emptyFolderCount == 1)
        precondition(!manager.fileExists(atPath: settings.baseDirectory), "预览不得创建目标目录")
        precondition(scan.errors.isEmpty)
        precondition(!PatrolScanner.scan(folders: [root.appendingPathComponent("missing")], configuration: config).errors.isEmpty)
        // 预览后修改文件必须被排除；未勾选的文件不在执行集合中。
        try Data("changed".utf8).write(to: course)
        let selected = scan.candidates.filter { $0.url != project }
        let valid = PatrolScanner.revalidated(selected, folders: [input], configuration: config)
        precondition(valid.map(\.path) == [screenshot.path], "复核结果：\(valid)")
        let result = await Task.detached { FileOrganizer.organize(valid, settings: config) }.value
        precondition(result.movedCount == 1 && result.failures.isEmpty)
        precondition(manager.fileExists(atPath: course.path) && manager.fileExists(atPath: project.path))
        let item = result.movedItems[0]
        let operation = SortOperation(source: "自动巡查", items: [item], duplicateCount: 0, duplicateBytes: 0, failureCount: 0)
        precondition(HistorySearch.matches(operation, query: "截图", category: "全部分类"))
        precondition(!HistorySearch.matches(operation, query: "不存在", category: "全部分类"))
        precondition(!HistorySearch.matches(operation, query: "截图", category: "文档"))
        let renamed = FileMoveRecord(originalPath: "/old/原始名.pdf", destinationPath: "/new/新名.pdf", categoryName: "文档")
        precondition(HistorySearch.matches(renamed, operation: operation, query: "原始名", category: "文档"))
        let failed = SortOperation(source: "网页", items: [], duplicateCount: 0, duplicateBytes: 0, failureCount: 1, failureMessages: ["demo.pdf 下载失败"])
        precondition(HistorySearch.matches(failed, query: "demo", category: "全部分类"))
        // 同内容保持原处，同名不同内容编号；撤回冲突绝不覆盖。
        try Data(contentsOf: URL(fileURLWithPath: item.destinationPath)).write(to: screenshot)
        precondition(FileOrganizer.organize([screenshot], settings: config).duplicateCount == 1)
        try Data("different".utf8).write(to: screenshot)
        let collision = FileOrganizer.organize([screenshot], settings: config)
        precondition(collision.movedItems.first?.fileName == "截图-样例-2.png")
        try Data("keep".utf8).write(to: screenshot)
        precondition(FileOrganizer.undo(result.movedItems).restoredCount == 0)
        let preserved = try Data(contentsOf: screenshot)
        precondition(preserved == Data("keep".utf8))
        try manager.removeItem(at: screenshot)
        precondition(FileOrganizer.undo(result.movedItems).restoredCount == 1)
        settings.baseDirectory = input.path
        precondition(PatrolScanner.scan(folders: [input], configuration: SortingConfiguration(settings: settings)).candidates.isEmpty)
        // 服务层确认：预览阻止立即巡查，设置变化要求刷新，确认只移动勾选项。
        settings.baseDirectory = root.appendingPathComponent("service-output").path
        let serviceFile = try file("service.txt")
        let history = OperationHistoryStore(historyURL: root.appendingPathComponent("test-history.json"))
        let service = FolderPatrolService(settings: settings, history: history, events: PetEventStore(), folderProvider: { [input] })
        func waitForService() async throws {
            for _ in 0..<500 {
                if !service.isRunning { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            preconditionFailure("巡查服务未按时结束")
        }
        service.preparePreview()
        try await waitForService()
        service.patrolNow()
        precondition(manager.fileExists(atPath: serviceFile.path))
        settings.smartNamingStyle = .dateOriginal
        service.confirmPreview(selectedIDs: [serviceFile.path])
        precondition(service.previewMessage.contains("设置已变化"))
        service.preparePreview()
        try await waitForService()
        service.confirmPreview(selectedIDs: [serviceFile.path])
        try await waitForService()
        precondition(!manager.fileExists(atPath: serviceFile.path))
        precondition(manager.fileExists(atPath: project.path))
        precondition(history.operations.first?.items.count == 1)
        service.closePreview()
        precondition(!service.isPreviewing)
        print("PASS: templates, history search, scan exclusions, non-mutating preview, revalidation, duplicates, collision, undo")
    }
}
