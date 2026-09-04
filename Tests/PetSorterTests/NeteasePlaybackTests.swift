import Foundation

@main
struct NeteasePlaybackTests {
    static func main() {
        func state(_ items: [(String, Bool?)]) -> Bool? {
            NeteasePlaybackParser.playingState(in: items.map { .init(title: $0.0, enabled: $0.1) })
        }
        precondition(state([("暂停", true), ("下一首", true)]) == true)
        precondition(state([("播放", true), ("上一首", true)]) == false)
        precondition(state([(" Play \n", true)]) == false)
        precondition(state([("Pause", true)]) == true)
        precondition(state([("暫停", true)]) == true)
        precondition(state([("继续播放", true)]) == false)
        precondition(state([("暂停", false)]) == nil)
        precondition(state([("播放", nil)]) == nil)
        precondition(state([("暂停", true), ("播放", true)]) == nil)
        precondition(state([("暂停", false), ("播放", true)]) == false)
        precondition(state([("暂停", true), ("暂停", true)]) == true)
        precondition(state([]) == nil)
        // “播放/暂停”没有当前状态；“播放全部”等不是当前播放器动作。
        precondition(state([("播放/暂停", true), ("Play/Pause", true), ("播放全部", true), ("暂停下载", true)]) == nil)
        precondition(NeteasePlaybackParser.isControlsMenu("控制"))
        precondition(NeteasePlaybackParser.isControlsMenu("Controls"))
        precondition(!NeteasePlaybackParser.isControlsMenu("播放列表"))
        print("通过：网易云菜单播放/暂停、中英文、禁用项、缺失权限属性、组合动作、冲突和未知状态")
    }
}
