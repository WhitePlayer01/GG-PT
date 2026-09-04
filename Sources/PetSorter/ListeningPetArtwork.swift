import SwiftUI

/// 听歌形态采用固定节奏的轻晃，不声称与歌曲的真实节拍同步。
struct ListeningPetArtwork: View {
    var quiet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playlist = ListeningAnimationPlaylist()
    @State private var variant: ListeningAnimationVariant = .sway
    @State private var startedAt = Date()
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        TimelineView(.animation(minimumInterval: quiet || lowPower ? 1.0 / 12.0 : 1.0 / 24.0, paused: reduceMotion)) { context in
            ListeningPetFrame(time: reduceMotion ? 0 : max(0, context.date.timeIntervalSince(startedAt)),
                              still: reduceMotion, variant: variant, intensity: quiet ? 0.35 : 1)
                .id(variant)
                .transition(.opacity)
        }
        .onAppear { variant = playlist.next(); startedAt = Date() }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: UInt64(ListeningAnimationVariant.segmentDuration * 1_000_000_000)) }
                catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.45)) {
                    variant = playlist.next()
                    startedAt = Date()
                }
            }
        }
        .accessibilityLabel("关羽正在听歌：\(variant.title)")
    }
}

/// 固定时间帧也用于导出与实时动画一致的 GIF 预览。
struct ListeningPetFrame: View {
    let time: TimeInterval
    var still = false
    var variant: ListeningAnimationVariant = .sway
    var intensity: Double = 1
    private let gold = Color(red: 0.92, green: 0.71, blue: 0.31)
    private static func artwork(for variant: ListeningAnimationVariant) -> NSImage? {
        let path = Bundle.main.url(forResource: variant.artworkName, withExtension: "png")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Resources/\(variant.artworkName).png")
        return ArtworkCache.image(at: path)
    }

    private func movement(_ phase: Double) -> (rotation: Double, x: Double, y: Double, stretch: Double) {
        guard !still else { return (0, 0, 0, 1) }
        switch variant {
        case .sway: return (sin(phase) * 3.2, 0, -abs(sin(phase)) * 3, 1 + sin(phase * 2) * 0.006)
        case .nod: return (sin(phase) * 1.2, 0, sin(phase * 2) * 3, 1 + sin(phase * 2) * 0.020)
        case .beat: return (sin(phase * 2) * 4, sin(phase) * 2, -abs(sin(phase * 2)) * 7, 1)
        case .dance: return (sin(phase) * 5.5, sin(phase) * 5, -abs(sin(phase)) * 4, 1)
        case .zen: return (sin(phase) * 1, 0, sin(phase) * 5, 1 + sin(phase) * 0.005)
        }
    }

    var body: some View {
        let phase = time.truncatingRemainder(dividingBy: 3.2) / 3.2 * .pi * 2
        let rawMotion = movement(phase)
        let motion = (rotation: rawMotion.rotation * intensity, x: rawMotion.x * intensity,
                      y: rawMotion.y * intensity, stretch: 1 + (rawMotion.stretch - 1) * intensity)
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.10))
                .frame(width: 118, height: 12)
                .scaleEffect(x: still ? 1 : 1 + sin(phase) * 4 * intensity / 118, y: 1)
                .offset(y: 123)
            if !still {
                ForEach(0..<3) { index in
                    let progress = (time / 2.4 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                    Image(systemName: index == 1 ? "music.quarternote.3" : "music.note")
                        .font(.system(size: index == 1 ? 18 : 15, weight: .semibold))
                        .foregroundStyle(index == 1 ? Color(red: 0.23, green: 0.64, blue: 0.43) : gold)
                        .opacity(sin(progress * .pi) * (0.4 + 0.45 * intensity))
                        .rotationEffect(.degrees(-14 + progress * 28))
                        .offset(x: (index == 1 ? -1 : 1) * (88 + sin(progress * .pi) * 12),
                                y: 5 - progress * 100)
                }
            }
            if let artwork = Self.artwork(for: variant) ?? Self.artwork(for: .sway) {
                Image(nsImage: artwork)
                    .resizable().scaledToFit()
                    .frame(width: 214, height: 263)
                    .scaleEffect(x: 1, y: motion.stretch, anchor: .bottom)
                    .rotationEffect(.degrees(motion.rotation), anchor: UnitPoint(x: 0.5, y: 0.88))
                    .offset(x: motion.x, y: motion.y)
            }
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<5) { index in
                    Capsule()
                        .fill(gold.opacity(0.85))
                        .frame(width: 3, height: 15)
                        .scaleEffect(x: 1, y: (still ? 5 : 5 + (sin(phase * 3 + Double(index) * 1.1) + 1) * 5 * intensity) / 15)
                }
            }
            .frame(height: 18)
            .offset(x: 82, y: 99)
        }
        .frame(width: 245, height: 275)
    }
}
