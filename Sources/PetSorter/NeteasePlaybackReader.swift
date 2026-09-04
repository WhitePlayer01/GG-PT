import AppKit
import ApplicationServices

struct NeteaseReading {
    var isPlaying: Bool?
    var message: String
}

/// 读取网易云原生「控制」菜单的辅助功能属性，不获取图像、音频，也不点击菜单。
enum NeteasePlaybackReader {
    static let bundleID = "com.netease.163music"

    @MainActor
    static func requestAccess() {
        // 只允许连接按钮触发授权提示，后台轮询不会反复弹窗。
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    static func read() async -> NeteaseReading {
        guard AXIsProcessTrusted() else {
            return .init(isPlaying: nil, message: "请点击“连接网易云”，在辅助功能中允许云长卫读取播放状态")
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return .init(isPlaying: false, message: "网易云音乐未运行")
        }
        let pid = app.processIdentifier
        // 跨进程读取可能超时，放到后台并限制总耗时，避免卡住桌宠和设置窗口。
        return await Task.detached(priority: .utility) { readMenu(pid: pid) }.value
    }

    private static func readMenu(pid: pid_t) -> NeteaseReading {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
        func children(_ element: AXUIElement) -> [AXUIElement] {
            (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        }
        // Chromium 客户端可能延迟创建辅助功能树。这只启用语义属性，不切换播放或窗口。
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        guard let value = attribute(app, kAXMenuBarAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return .init(isPlaying: nil, message: "暂时无法读取网易云菜单，请检查辅助功能授权")
        }
        let menuBar = value as! AXUIElement
        let controls = children(menuBar).filter {
            NeteasePlaybackParser.isControlsMenu(attribute($0, kAXTitleAttribute) as? String ?? "")
        }
        var items: [NeteaseMenuItem] = []
        var visited = 0
        func collect(_ element: AXUIElement, depth: Int) {
            guard depth <= 3, visited < 80, ProcessInfo.processInfo.systemUptime < deadline else { return }
            visited += 1
            if attribute(element, "AXHidden") as? Bool == true { return }
            if attribute(element, kAXRoleAttribute) as? String == kAXMenuItemRole {
                items.append(.init(title: attribute(element, kAXTitleAttribute) as? String ?? "",
                                   enabled: attribute(element, kAXEnabledAttribute) as? Bool))
                // 不遍历菜单项的子菜单，避免把其他播放操作当成主播放器状态。
                return
            }
            for child in children(element) { collect(child, depth: depth + 1) }
        }
        for control in controls { collect(control, depth: 0) }
        // 部分读取或超时不应拿旧菜单推断播放。
        guard ProcessInfo.processInfo.systemUptime < deadline,
              let playing = NeteasePlaybackParser.playingState(in: items) else {
            return .init(isPlaying: nil, message: "网易云播放状态未知；当前版本未提供明确的播放／暂停菜单状态")
        }
        return .init(isPlaying: playing,
                     message: playing ? "网易云正在播放 · 仅状态，暂不记录歌名" : "网易云已暂停或停止")
    }
}

struct NeteaseMenuItem {
    let title: String
    let enabled: Bool?
}

enum NeteasePlaybackParser {
    static func isControlsMenu(_ title: String) -> Bool {
        ["控制", "播放控制", "controls", "control", "playback"].contains(normalized(title))
    }

    /// 菜单显示「暂停」表示当前正在播放；「播放」表示当前暂停或停止。
    /// 必须是可用且语义明确的单一动作；组合按钮、禁用项、冲突和缺失均为未知。
    static func playingState(in items: [NeteaseMenuItem]) -> Bool? {
        var states: Set<Bool> = []
        for item in items where item.enabled == true {
            switch normalized(item.title) {
            case "暂停", "暫停", "pause": states.insert(true)
            case "播放", "继续播放", "繼續播放", "play", "resume": states.insert(false)
            default: break
            }
        }
        return states.count == 1 ? states.first : nil
    }

    private static func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
