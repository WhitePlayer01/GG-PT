import AppKit
import Combine

/// 使用播放器公开脚本接口和浏览器提供的媒体信息，不录音、不录屏。
@MainActor
final class MusicListeningService: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var neteaseStatus = "网易云尚未连接"
    @Published private(set) var currentTrack: MusicTrack?
    @Published private(set) var status = "听歌记录已关闭"
    let history = MusicHistoryStore()
    private let settings: SettingsStore
    private var subscription: AnyCancellable?
    private var timer: Timer?
    private var polling = false
    private var continuity = PlaybackContinuity()
    private var activeSourceID: String?
    private var generation = 0
    private var neteaseSubscription: AnyCancellable?
    private var browserLastSeen: Date?
    private var browserSourceID: String?
    private let queue = DispatchQueue(label: "com.local.PetSorter.music-reader", qos: .utility)

    init(settings: SettingsStore) { self.settings = settings }

    func start() {
        subscription = settings.$musicTrackingEnabled.removeDuplicates().sink { [weak self] enabled in
            self?.configure(enabled)
        }
        neteaseSubscription = settings.$neteaseTrackingEnabled.removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.configure(self.settings.musicTrackingEnabled)
            }
        }
    }

    private func configure(_ enabled: Bool) {
        generation += 1
        timer?.invalidate()
        timer = nil
        currentTrack = nil
        isPlaying = false
        continuity.reset()
        activeSourceID = nil
        browserLastSeen = nil
        browserSourceID = nil
        history.endSession()
        status = enabled ? "等待播放歌曲…" : "听歌记录已关闭"
        guard enabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer?.tolerance = 1
        // @Published 在属性写入前发送事件，下一轮再读取设置。
        DispatchQueue.main.async { [weak self] in self?.poll() }
    }

    func connectNetease() {
        settings.neteaseTrackingEnabled = true
        settings.musicTrackingEnabled = true
        NeteasePlaybackReader.requestAccess()
        poll()
    }

    func poll() {
        guard settings.musicTrackingEnabled, !polling else { return }
        polling = true
        let token = generation
        Task {
            var fallback: String?
            if settings.neteaseTrackingEnabled,
               !NSRunningApplication.runningApplications(withBundleIdentifier: NeteasePlaybackReader.bundleID).isEmpty {
                let result = await NeteasePlaybackReader.read()
                guard token == generation, settings.musicTrackingEnabled else { polling = false; return }
                if neteaseStatus != result.message { neteaseStatus = result.message }
                fallback = result.message
                if result.isPlaying == true {
                    accept(nil, playing: true, position: nil, sourceID: NeteasePlaybackReader.bundleID)
                    if status != result.message { status = result.message }
                    polling = false
                    return
                }
                if result.isPlaying == nil, activeSourceID == NeteasePlaybackReader.bundleID, isPlaying {
                    // 辅助功能读取暂时不可用不等于暂停；仅延续外观，不累计未知期间的历史。
                    accept(nil, playing: nil, position: nil)
                    let message = result.message + " · 保持听歌形态"
                    if status != message { status = message }
                    polling = false
                    return
                }
                if activeSourceID == NeteasePlaybackReader.bundleID {
                    accept(nil, playing: false, position: nil)
                }
            } else if settings.neteaseTrackingEnabled {
                if activeSourceID == NeteasePlaybackReader.bundleID { accept(nil, playing: false, position: nil) }
                if neteaseStatus != "请打开网易云音乐" { neteaseStatus = "请打开网易云音乐" }
                fallback = neteaseStatus
            }
            if let last = browserLastSeen {
                if Date().timeIntervalSince(last) < 12 { polling = false; return }
                browserLastSeen = nil
            }
            pollScriptPlayers(token: token, fallback: fallback)
        }
    }

    private func pollScriptPlayers(token: Int, fallback: String?) {
        let players = [("com.apple.Music", "Apple Music"), ("com.spotify.client", "Spotify")]
            .filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.0).isEmpty }
        guard !players.isEmpty else {
            accept(nil, playing: false, position: nil)
            let message = fallback ?? "等待网易云、Apple Music、Spotify 或音乐网页播放"
            if status != message { status = message }
            polling = false
            return
        }
        queue.async { [weak self] in
            var found: (MusicTrack, Double?)?
            var failure: String? = fallback
            var failedSources: Set<String> = []
            for (bundleID, name) in players {
                let durationExpression = bundleID == "com.spotify.client" ? "(duration of current track) / 1000" : "duration of current track"
                let source = """
                with timeout of 3 seconds
                    tell application id "\(bundleID)"
                        if not running then return {}
                        if player state is not playing then return {}
                        return {name of current track, artist of current track, album of current track, \(durationExpression), player position}
                    end tell
                end timeout
                """
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    failedSources.insert(bundleID)
                    let code = error[NSAppleScript.errorNumber] as? Int
                    failure = code == -1743 ? "请在系统设置 → 隐私与安全性 → 自动化中允许云长卫读取\(name)" : "暂时无法读取\(name)的歌曲信息"
                    continue
                }
                guard let result, result.numberOfItems == 5,
                      let title = result.atIndex(1)?.stringValue, !title.isEmpty else { continue }
                let duration = result.atIndex(4)?.doubleValue ?? 0
                found = (MusicTrack(title: title, artist: result.atIndex(2)?.stringValue ?? "",
                                    album: result.atIndex(3)?.stringValue ?? "", source: name,
                                    sourceID: bundleID, duration: duration > 0 ? duration : nil), result.atIndex(5)?.doubleValue)
                break
            }
            let output = found
            let message = failure
            let failures = failedSources
            DispatchQueue.main.async {
                guard let self else { return }
                self.polling = false
                guard token == self.generation, self.settings.musicTrackingEnabled else { return }
                if let last = self.browserLastSeen, Date().timeIntervalSince(last) < 12 { return }
                let unknown = output == nil && failures.contains(self.activeSourceID ?? "")
                self.accept(output?.0, playing: unknown ? nil : output != nil, position: output?.1)
                if output == nil, let message, self.status != message { self.status = message }
            }
        }
    }

    func receiveBrowser(_ values: [String: String]) -> BrowserBridgeResponse {
        guard settings.musicTrackingEnabled else { return .init(success: false, message: "请先在听歌记录中开启自动记录") }
        guard let host = values["host"], Self.musicHosts.contains(host),
              let title = values["title"], title.count <= 500,
              let artist = values["artist"], artist.count <= 500,
              let session = values["session"], session.count <= 100 else {
            return .init(success: false, message: "歌曲信息无效")
        }
        if isPlaying, settings.neteaseTrackingEnabled, activeSourceID == NeteasePlaybackReader.bundleID {
            return .init(success: true, message: "正在检测网易云桌面播放状态")
        }
        let sourceID = "web:\(host):\(session)"
        let playing = values["playing"] == "true"
        // 其他已暂停的标签页不能覆盖正在播放的标签页。
        if !playing && (browserSourceID != sourceID || browserLastSeen == nil) {
            return .init(success: true, message: "已忽略未播放页面")
        }
        guard !playing || (!title.isEmpty && !artist.isEmpty) else {
            return .init(success: false, message: "页面未提供完整歌名和歌手")
        }
        if playing, let last = browserLastSeen, Date().timeIntervalSince(last) < 12,
           let active = browserSourceID, active != sourceID {
            return .init(success: true, message: "正在记录另一音乐页面")
        }
        browserSourceID = sourceID
        browserLastSeen = playing ? Date() : nil
        func number(_ key: String) -> Double? {
            guard let value = Double(values[key] ?? ""), value.isFinite, value >= 0 else { return nil }
            return value
        }
        let track = MusicTrack(title: title, artist: artist, album: String((values["album"] ?? "").prefix(500)),
                               source: host, sourceID: "web:\(host)", duration: number("duration"))
        accept(track, playing: playing, position: number("position"))
        return .init(success: true, message: "歌曲信息已接收")
    }

    static let musicHosts: Set<String> = ["music.163.com", "y.qq.com", "open.spotify.com", "music.apple.com", "music.youtube.com"]

    private func accept(_ track: MusicTrack?, playing: Bool?, position: Double?, sourceID: String? = nil) {
        continuity.observe(playing)
        if isPlaying != continuity.isPlaying { isPlaying = continuity.isPlaying }
        if let playing {
            let nextTrack = playing ? track : nil
            if currentTrack != nextTrack { currentTrack = nextTrack }
            activeSourceID = playing ? (sourceID ?? track?.sourceID) : nil
            let message = playing
                ? (track.map { "正在记录 · \($0.source)" } ?? "网易云正在播放 · 仅状态，暂不记录歌名")
                : "等待播放歌曲…"
            if status != message { status = message }
        }
        // 未知状态只延续外观，历史计时必须有本轮实际的播放观测。
        history.observe(track, playing: playing == true, position: position)
    }
}
