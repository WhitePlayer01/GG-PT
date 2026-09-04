import Foundation

func checkEqual<T: Equatable>(_ actual: T, _ expected: T) { precondition(actual == expected, "Expected \(expected), received \(actual)") }
func checkTrue(_ value: Bool) { precondition(value) }
func checkNotNil<T>(_ value: T?) { precondition(value != nil) }

final class MusicHistoryTests {
    @MainActor
    func testPlaybackPauseSeekSleepReplayAndReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("music.json")
        let store = MusicHistoryStore(fileURL: file)
        let track = MusicTrack(title: "测试歌曲", artist: "测试歌手", album: "专辑", source: "测试播放器", sourceID: "test", duration: 120)
        let date = Date(timeIntervalSince1970: 1000)
        func hear(_ seconds: Double, _ position: Double, _ playing: Bool = true) {
            store.observe(track, playing: playing, position: position, at: date.addingTimeInterval(seconds))
        }
        hear(0, 0)
        hear(5, 5)
        hear(10, 10)
        checkEqual(store.records.count, 1)
        checkEqual(store.records[0].listenedSeconds, 10)
        hear(15, 10, false)
        hear(300, 10)
        hear(305, 15)
        checkEqual(store.records.count, 1)
        checkEqual(store.records[0].listenedSeconds, 15)
        hear(310, 80) // 向前拖动
        hear(315, 0) // 向后拖动不当作完整重播
        checkEqual(store.records.count, 1)
        checkEqual(store.records[0].listenedSeconds, 15)
        hear(600, 90) // 休眠间隔不累计
        checkEqual(store.records[0].listenedSeconds, 15)
        hear(605, 115)
        hear(610, 0) // 接近结尾回到开头才识别为单曲循环
        checkEqual(store.records.count, 2)
        hear(615, 5)
        checkEqual(store.records[0].listenedSeconds, 5)
        let reloaded = MusicHistoryStore(fileURL: file)
        checkEqual(reloaded.records.count, 2)
        checkEqual(reloaded.records[0].track.title, track.title)
        checkEqual(reloaded.records[0].listenedSeconds, 5)
        store.observe(MusicTrack(title: "第二首", artist: "歌手", album: "", source: "测试", sourceID: "test", duration: nil), playing: true, position: nil, at: date.addingTimeInterval(620))
        checkEqual(store.records.count, 3)
        store.endSession()
        hear(625, 10)
        checkEqual(store.records.count, 4)
        let exported = directory.appendingPathComponent("export.json")
        store.export(to: exported)
        checkTrue(try String(contentsOf: exported, encoding: .utf8).contains("1970-01-01T"))
        store.clear()
        checkTrue(MusicHistoryStore(fileURL: file).records.isEmpty)
    }

    @MainActor
    func testCorruptHistoryIsPreservedAndNoEmptyOrPausedRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("music.json")
        let broken = Data("broken history".utf8)
        try broken.write(to: file)
        let store = MusicHistoryStore(fileURL: file)
        let track = MusicTrack(title: "测试", artist: "", album: "", source: "", sourceID: "", duration: nil)
        store.observe(track, playing: true, position: nil)
        checkNotNil(store.errorMessage)
        checkEqual(try Data(contentsOf: file), broken)
        store.clear()
        store.observe(track, playing: false, position: nil)
        store.observe(nil, playing: true, position: nil)
        checkTrue(store.records.isEmpty)
        store.observe(track, playing: true, position: nil)
        checkEqual(store.records.count, 1)
    }
}

@main
struct MusicHistoryTestRunner {
    @MainActor static func main() throws {
        let tests = MusicHistoryTests()
        try tests.testPlaybackPauseSeekSleepReplayAndReload()
        try tests.testCorruptHistoryIsPreservedAndNoEmptyOrPausedRecords()
        print("通过：暂停恢复、拖动进度、休眠、单曲循环、切歌、重启、导出、清空及损坏文件保护")
    }
}
