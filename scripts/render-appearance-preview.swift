import AppKit
import SwiftUI

/* 渲染真实 SwiftUI 外观编辑器，用于检查明暗外观和窄窗口排版。
 不启动桌宠或后台服务，不提交外观设置。 */
@main
struct AppearancePreviewRenderer {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: "GTF/外观与动画设置-2026-09-04")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings = SettingsStore()
        settings.appearanceDraft = AppearanceProfile()
        settings.appearanceEditingIndex = 0
        for (name, dark, width, scene) in [("浅色", false, 690.0, ArtworkScene.idle),
                                          ("深色听歌", true, 730.0, ArtworkScene.listening),
                                          ("窄窗口", false, 610.0, ArtworkScene.idle)] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let content = VStack(alignment: .leading, spacing: 20) {
                Text("外观与动画").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("三套外观方案，为每个场景选择图片与动画").foregroundStyle(.secondary)
                AppearanceSettingsView(settings: settings, selectedScene: scene)
            }
            .padding(24).frame(width: width)
            .groupBoxStyle(SettingsGroupStyle())
            .tint(SettingsPalette.accent).accentColor(SettingsPalette.accent)
            .background(SettingsPalette.canvas)
            .environment(\.colorScheme, dark ? .dark : .light)
            let host = NSHostingView(rootView: content)
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("预览渲染失败") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("预览保存失败") }
            let file = directory.appendingPathComponent("\(name).png")
            try data.write(to: file)
            print(file.path)
        }
    }
}
