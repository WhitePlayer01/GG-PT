import AppKit
import SwiftUI

/* 渲染真实 SwiftUI 设置与确认界面，只注入临时示例文件。
 不启动常驻服务，不读取用户历史；图片明确标为开发版示例。 */
@main struct OrganizationPreviewRenderer {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let manager = FileManager.default
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("sort-preview-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let defaults = OrganizationTestDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.baseDirectory = root.appendingPathComponent("收纳箱").path
        settings.organizeByMonthFolder = false
        settings.sortingRules = SortingRuleTemplate.allCases.map { $0.makeRule() }
        let input = root.appendingPathComponent("下载示例")
        try manager.createDirectory(at: input, withIntermediateDirectories: true)
        var urls: [URL] = []
        for name in ["课程讲义.pdf", "项目计划.docx", "截图-灵感.png"] {
            let url = input.appendingPathComponent(name)
            try Data(("仅供界面示例：" + name).utf8).write(to: url)
            try manager.setAttributes([.modificationDate: Date().addingTimeInterval(-120)], ofItemAtPath: url.path)
            urls.append(url)
        }
        let history = OperationHistoryStore(historyURL: root.appendingPathComponent("history.json"))
        let events = PetEventStore()
        let patrol = FolderPatrolService(settings: settings, history: history, events: events, folderProvider: { [input] })
        let music = MusicListeningService(settings: settings, history: MusicHistoryStore(fileURL: root.appendingPathComponent("music.json")))
        let updates = UpdateService()
        let output = URL(fileURLWithPath: "output/organization-preview", isDirectory: true)
        try manager.createDirectory(at: output, withIntermediateDirectories: true)
        patrol.preparePreview()
        for _ in 0..<500 where patrol.isRunning { try await Task.sleep(nanoseconds: 10_000_000) }
        guard !patrol.isRunning else { fatalError("预览扫描超时") }
        try render(PatrolPreviewSheet(patrol: patrol), name: "patrol", width: 768, output: output)
        patrol.closePreview()
        let result = FileOrganizer.organize(urls, settings: settings)
        history.record(result, source: "示例文件整理")
        for section in [SettingsSection.history, .rules] {
            let view = SettingsView(settings: settings, history: history, updates: updates, music: music, patrol: patrol, selectedSection: section)
            try render(view, name: section == .history ? "history" : "rules", width: 1100, output: output)
        }
    }

    @MainActor static func render<V: View>(_ view: V, name: String, width: CGFloat, output: URL) throws {
        NSApp.appearance = NSAppearance(named: .aqua)
        let content = VStack(alignment: .leading, spacing: 0) {
            Text("云长卫 · 开发版界面 / 示例文件").font(.caption).padding(12)
            view
        }.frame(width: width, height: name == "patrol" ? 625 : 850).environment(\.colorScheme, .light).background(Color.white)
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("无法渲染") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("无法导出") }
        try data.write(to: output.appendingPathComponent(name + ".png"))
        print(output.appendingPathComponent(name + ".png").path)
    }
}
