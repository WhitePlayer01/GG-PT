import AppKit
import SwiftUI

/// 独立渲染常规设置，不启动桌宠、目录巡查或音乐监听。
@main
struct SettingsPreviewRenderer {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
        let settings = SettingsStore()
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let content = VStack(alignment: .leading, spacing: 20) {
                Text("常规").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("收纳位置、桌宠外观与基础分类").foregroundStyle(.secondary)
                GeneralSettingsView(settings: settings)
            }
            .padding(24)
            .frame(width: 730)
            .groupBoxStyle(SettingsGroupStyle())
            .tint(SettingsPalette.accent)
            .accentColor(SettingsPalette.accent)
            .background(SettingsPalette.canvas)
            .environment(\.colorScheme, dark ? .dark : .light)
            // AppKit 控件无法由 ImageRenderer 输出，使用真实原生视图快照。
            let host = NSHostingView(rootView: content)
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                fatalError("设置预览渲染失败")
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                fatalError("设置预览导出失败")
            }
            let path = "output/settings-\(dark ? "dark" : "light").png"
            try data.write(to: URL(fileURLWithPath: path))
            print(path)
        }
    }
}
