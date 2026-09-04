import Foundation

@main
struct ListeningPlaybackTests {
    struct SeededRandom: RandomNumberGenerator {
        var state: UInt64 = 12345
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }
    static func main() {
        var random = SeededRandom()
        var playlist = ListeningAnimationPlaylist()
        var last: ListeningAnimationVariant?
        var orders: Set<String> = []
        for _ in 0..<100 {
            let batch = (0..<5).map { _ in playlist.next(using: &random) }
            precondition(Set(batch).count == 5, "一轮必须包含五种不同动画")
            for current in batch {
                precondition(current != last, "轮内及换轮边界不能连续重复")
                last = current
            }
            orders.insert(batch.map(\.rawValue).joined(separator: ","))
        }
        precondition(orders.count > 1, "每轮需要重新随机洗牌")
        var playback = PlaybackContinuity()
        playback.observe(nil)
        precondition(!playback.isPlaying, "没有播放证据时不能自行开始")
        playback.observe(true)
        for _ in 0..<100 {
            playback.observe(nil)
            precondition(playback.isPlaying, "窗口短暂不可读不能打断播放形态")
        }
        playback.observe(false)
        precondition(!playback.isPlaying, "明确暂停必须退出")
        playback.observe(true)
        playback.reset()
        precondition(!playback.isPlaying, "关闭识别或退出播放器必须停止")
        print("通过：五款覆盖、100 轮洗牌、边界不重复、未知状态保持、明确暂停和关闭复位")
    }
}
