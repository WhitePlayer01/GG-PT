import Foundation

// 每段包含完整的 9.6 秒动作周期；五套全部出现后再洗牌。
enum ListeningAnimationVariant: String, CaseIterable, Identifiable {
    case sway, nod, beat, dance, zen
    var id: String { rawValue }
    static let segmentDuration: TimeInterval = 9.6
    var title: String {
        switch self {
        case .sway: return "闭眼轻晃"
        case .nod: return "扶耳点头"
        case .beat: return "握拳打拍"
        case .dance: return "张臂摇摆"
        case .zen: return "盘坐沉浸"
        }
    }
    var artworkName: String { self == .sway ? "guan-yu-listening" : "guan-yu-listening-\(rawValue)" }
}

struct ListeningAnimationPlaylist {
    private var remaining: [ListeningAnimationVariant] = []
    private(set) var previous: ListeningAnimationVariant?

    mutating func next() -> ListeningAnimationVariant {
        var random = SystemRandomNumberGenerator()
        return next(using: &random)
    }

    mutating func next<R: RandomNumberGenerator>(using random: inout R) -> ListeningAnimationVariant {
        if remaining.isEmpty {
            remaining = ListeningAnimationVariant.allCases.shuffled(using: &random)
            if remaining.last == previous {
                remaining.swapAt(0, remaining.count - 1)
            }
        }
        let value = remaining.removeLast()
        previous = value
        return value
    }
}

/// 区分“已暂停”和“暂时读不到”。后者只保留外观，不推算收听时间。
struct PlaybackContinuity {
    private(set) var isPlaying = false
    mutating func observe(_ playing: Bool?) {
        if let playing { isPlaying = playing }
    }
    mutating func reset() { isPlaying = false }
}
