import AppKit
import Combine

// 独立测试使用内存设置，不修改用户偏好。
@MainActor final class SettingsStore: ObservableObject {
    @Published var musicTrackingEnabled = true
    @Published var neteaseTrackingEnabled = true
    @Published var neteaseSongRecognitionEnabled = true
}
struct BrowserBridgeResponse { let success: Bool; let message: String }

@main struct MusicServicePlaybackTests {
    @MainActor static func main() async {
        let settings = SettingsStore()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let history = MusicHistoryStore(fileURL: file)
        var playing: Bool? = true
        var completion: CheckedContinuation<(track: MusicTrack?, message: String), Never>?
        var reads = 0
        let service = MusicListeningService(settings: settings, history: history,
            neteaseRunning: { true },
            readPlayback: { reads += 1; return .init(isPlaying: playing, message: "test") },
            readSong: { await withCheckedContinuation { completion = $0 } })
        func drain() async { for _ in 0..<30 { await Task.yield() } }
        service.poll()
        await drain()
        precondition(service.isPlaying, "歌曲读取 尚未完成也必须立即进入听歌形态")
        precondition(completion != nil, "歌曲任务应在后台运行")
        let firstReads = reads
        service.poll(); await drain()
        precondition(reads > firstReads, "歌曲读取 挂起不能阻塞下一轮播放检测")
        playing = nil
        service.poll(); await drain()
        precondition(service.isPlaying, "未知状态应保留已经确认的听歌形态")
        completion?.resume(returning: (nil, "未授权")); completion = nil
        await drain()
        playing = false
        service.poll(); await drain()
        precondition(!service.isPlaying, "明确暂停应退出听歌形态")
        playing = true
        service.poll(); await drain()
        precondition(service.isPlaying)
        playing = false
        service.poll(); await drain()
        completion?.resume(returning: (MusicTrack(title: "过期歌曲", artist: "歌手", album: "", source: "网易云音乐", sourceID: NeteasePlaybackReader.bundleID, duration: nil), "stale"))
        completion = nil
        await drain()
        precondition(!service.isPlaying && service.currentTrack == nil, "迟到识别结果不能重新开启听歌形态")
        precondition(history.records.isEmpty, "未确认信息不能写入历史")
        settings.neteaseSongRecognitionEnabled = false
        playing = true
        service.poll(); await drain()
        precondition(service.isPlaying, "关闭歌曲识别仍需进入听歌形态")
        print("通过：歌曲读取 挂起立即听歌、持续轮询、未知保持、暂停退出、过期结果丢弃、关闭识别仍听歌")
    }
}
