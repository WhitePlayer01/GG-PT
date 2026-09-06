import AppKit
import ApplicationServices

/* 仅读取辅助功能提供的播放条文字，不创建截图或录屏会话。
 遍历限定窗口底部、节点数量和时间；无法取得完整文字时不猜测歌曲。 */
enum NeteaseSongReader {
    @MainActor static func requestAccess() { NeteasePlaybackReader.requestAccess() }

    @MainActor static func read() async -> (track: MusicTrack?, message: String) {
        guard AXIsProcessTrusted() else { return (nil, "请在辅助功能中允许读取网易云歌曲") }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: NeteasePlaybackReader.bundleID).first else {
            return (nil, "网易云音乐未运行")
        }
        let pid = app.processIdentifier
        return await Task.detached(priority: .utility) { readText(pid: pid) }.value
    }

    private static func readText(pid: pid_t) -> (track: MusicTrack?, message: String) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let deadline = ProcessInfo.processInfo.systemUptime + 1.5
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
        func frame(_ element: AXUIElement) -> CGRect? {
            guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
                  let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
            var point = CGPoint.zero
            var dimensions = CGSize.zero
            guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
                  AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
            return CGRect(origin: point, size: dimensions)
        }
        let windows = (attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter {
            guard attribute($0, kAXMinimizedAttribute) as? Bool != true, let rect = frame($0) else { return false }
            return rect.width >= 650 && rect.height >= 400
        }
        guard windows.count == 1, let window = windows.first, let bounds = frame(window) else {
            return (nil, "请打开网易云主窗口；当前无法读取播放条文字")
        }
        // 坐标只用于筛选语义控件，不读取屏幕像素；排除歌单正文和右侧工具。
        let region = CGRect(x: bounds.minX + 86, y: bounds.maxY - 80,
                            width: min(340, bounds.width * 0.32), height: 80)
        var lines: [String] = []
        var visited = 0
        var incomplete = false
        func collect(_ element: AXUIElement, depth: Int) {
            guard visited < 160, depth <= 16, ProcessInfo.processInfo.systemUptime < deadline else {
                incomplete = true; return
            }
            visited += 1
            if attribute(element, "AXHidden") as? Bool == true { return }
            let rect = frame(element)
            if let rect, !rect.isEmpty, !rect.intersects(region) { return }
            if attribute(element, kAXRoleAttribute) as? String == kAXStaticTextRole,
               let rect, !rect.isEmpty, region.contains(rect) {
                for key in [kAXValueAttribute, kAXTitleAttribute] {
                    if let text = attribute(element, key) as? String, !text.isEmpty, text.count <= 500 { lines.append(text) }
                }
                return
            }
            var count: CFIndex = 0
            guard ProcessInfo.processInfo.systemUptime < deadline,
                  AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count) == .success else { return }
            if count > 160 - visited { incomplete = true; return }
            var children: CFArray?
            if count > 0, AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, count, &children) == .success {
                for child in children as? [AXUIElement] ?? [] {
                    collect(child, depth: depth + 1)
                    if incomplete { return }
                }
            }
        }
        collect(window, depth: 0)
        guard !incomplete, ProcessInfo.processInfo.systemUptime < deadline, !lines.isEmpty else {
            return (nil, "网易云未提供可读取的完整播放条文字，暂只检测播放状态")
        }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.netease.163music/Data/Documents/storage/file_storage/webdata/file/playingList")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16_000_000,
              let data = try? Data(contentsOf: url),
              let track = NeteaseSongMatcher.match(lines: lines, queueData: data) else {
            return (nil, "播放条文字未与本地歌单唯一匹配，暂不写入记录")
        }
        return (track, "已通过辅助功能读取网易云歌曲")
    }
}

enum NeteaseSongMatcher {
    /// 必须同时出现完整歌名与歌手，且只命中一首歌；不将播放列表顺序作为播放证据。
    static func match(lines: [String], queueData: Data) -> MusicTrack? {
        guard let root = try? JSONSerialization.jsonObject(with: queueData) as? [String: Any],
              let entries = root["list"] as? [[String: Any]] else { return nil }
        let observed = Set(lines.map(normalize))
        var matches: [MusicTrack] = []
        for entry in entries {
            guard let track = entry["track"] as? [String: Any],
                  let title = track["name"] as? String, !normalize(title).isEmpty,
                  let artists = track["artists"] as? [[String: Any]] else { continue }
            let names = artists.compactMap { $0["name"] as? String }.filter { !normalize($0).isEmpty }
            guard !names.isEmpty, observed.contains(normalize(title)) else { continue }
            let artist = names.joined(separator: " / ")
            guard observed.contains(normalize(artist)) || names.allSatisfy({ observed.contains(normalize($0)) }) else { continue }
            let album = (track["album"] as? [String: Any])?["name"] as? String ?? ""
            let milliseconds = (track["duration"] as? NSNumber)?.doubleValue ?? 0
            let match = MusicTrack(title: title, artist: artist, album: album,
                                  source: "网易云音乐", sourceID: NeteasePlaybackReader.bundleID,
                                  duration: milliseconds > 0 ? milliseconds / 1000 : nil)
            if !matches.contains(where: { $0.key == match.key }) { matches.append(match) }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func normalize(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.lowercased()
            .filter { !$0.isWhitespace }
    }
}
