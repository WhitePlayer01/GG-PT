import SwiftUI
import UniformTypeIdentifiers

/// 桌宠对一次收纳任务的四种可见状态。
private enum PetVisualState: String {
    case idle
    case receiving
    case failure
    case complete

    var artworkName: String { "guan-yu-\(rawValue)" }
}

/// 展示可拖动、可接收 Finder 文件的关羽桌宠主界面。
struct PetView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var history: OperationHistoryStore
    @ObservedObject var events: PetEventStore
    @ObservedObject var music: MusicListeningService
    let openSettings: () -> Void
    let patrolNow: () -> Void

    @State private var isTargeted = false
    @State private var swordFrameIndex = 0
    @State private var isPlayingSwordAnimation = false
    @State private var message = "把文件交给关将军"
    @State private var messageVisible = true
    @State private var visualState: PetVisualState = .idle
    @State private var reactionOffset: CGFloat = 0
    @State private var reactionRotation = 0.0
    @State private var reactionScale: CGFloat = 1
    @State private var stateSequence = 0
    @State private var messageSequence = 0
    @State private var receivingVariation = 0
    @State private var resultVariation = 0

    /// 组合投放高亮、角色动画、设置入口和结果消息气泡。
    var body: some View {
        ZStack {
            ThemeAura(theme: effectiveTheme)

            if settings.seasonalEffectsEnabled, let moment = SeasonalMoment.current() {
                Image(systemName: moment.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(themeAccent.opacity(settings.quietMode ? 0.28 : 0.72))
                    .rotationEffect(.degrees(-4))
                    .offset(x: 87, y: -72)
                    .shadow(color: themeAccent.opacity(0.35), radius: 6)
                    .accessibilityLabel(moment.name)
            }

            if !isListening { WeaponAura(weapon: settings.petWeapon) }

            if isTargeted {
                // 文件悬停时显示金色接收区域，提示当前可以松手投放。
                Circle()
                    .fill(themeAccent.opacity(0.16))
                    .overlay(Circle().stroke(themeAccent.opacity(0.85), lineWidth: 3))
                    .frame(width: 250, height: 250)
                    .blur(radius: 0.3)
                    .transition(.scale.combined(with: .opacity))
            }

            if visualState == .complete && !isTargeted {
                Circle()
                    .stroke(themeAccent.opacity(0.38), lineWidth: 4)
                    .frame(width: 225, height: 225)
                    .transition(.scale.combined(with: .opacity))
            } else if visualState == .failure && !isTargeted {
                Circle()
                    .fill(Color.red.opacity(0.11))
                    .frame(width: 225, height: 225)
                    .transition(.opacity)
            }

            Group {
                if isListening {
                    ListeningPetArtwork(quiet: settings.quietMode)
                } else if isPlayingSwordAnimation {
                    SwordAnimationArtwork(frameIndex: swordFrameIndex, fallbackSkin: settings.petSkin)
                } else {
                    StatePetArtwork(state: isTargeted ? .receiving : visualState, skin: settings.petSkin)
                }
            }
                .scaledToFit()
                .frame(width: 245, height: 275)
                .scaleEffect(characterScale, anchor: .bottom)
                .rotationEffect(.degrees(isListening ? 0 : reactionRotation), anchor: .bottom)
                .offset(x: isListening ? 0 : reactionOffset, y: characterYOffset)
                // 听歌帧已有地面阴影，避免每帧对整个人物重新做模糊合成。
                .shadow(color: .black.opacity(isListening ? 0 : 0.18), radius: isListening ? 0 : 5, y: 4)

            VStack {
                HStack {
                    Spacer()
                    if settings.showsSettingsButton {
                        // 此按钮可以在设置中隐藏，右键菜单始终保留设置入口。
                        Button(action: openSettings) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(.black.opacity(0.62), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("设置收纳目录")
                    }
                }
                Spacer()
                if isListening && !isTargeted && (visualState == .idle || !messageVisible) {
                    VStack(spacing: 2) {
                        Label("将军正在听", systemImage: "headphones")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                        Text(music.currentTrack?.title ?? "此曲甚妙")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(messageBackground, in: Capsule())
                    .frame(maxWidth: 240)
                } else if messageVisible {
                    Text(message)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(messageBackground, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(10)

            if settings.showsDailyBadge, !messageVisible, !isListening {
                VStack {
                    Spacer()
                    HStack {
                        Label("今日 \(history.todaySummary.movedCount)", systemImage: "tray.full.fill")
                        Text("·")
                        Label("\(history.currentStreak) 天", systemImage: "flame.fill")
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(messageBackground.opacity(0.9), in: Capsule())
                    .padding(.bottom, 8)
                }
                .transition(.opacity)
            }
        }
        .frame(width: 270, height: 330)
        .scaleEffect(settings.petScale, anchor: .bottom)
        .frame(width: 270 * settings.petScale, height: 330 * settings.petScale)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: receive(providers:))
        .contextMenu {
            Text("今日已收 \(history.todaySummary.movedCount) 件 · 连续 \(history.currentStreak) 天")
            if let moment = SeasonalMoment.current(), settings.seasonalEffectsEnabled {
                Text("\(moment.name) · \(moment.greeting)")
            }
            Divider()
            if let track = music.currentTrack {
                Text("正在听：\(track.title) · \(track.artist)")
            }
            Toggle("自动记录听歌", isOn: $settings.musicTrackingEnabled)
            Button("收纳设置…", action: openSettings)
            Button("打开收纳箱", action: settings.revealBaseDirectory)
            Button("立即巡查桌面与下载", action: patrolNow)
                .disabled(!settings.monitorDesktop && !settings.monitorDownloads)
            Button("撤回上次收纳", action: undoLast)
                .disabled(!history.canUndo)
            Divider()
            Menu("角色皮肤") {
                ForEach(PetSkin.allCases) { skin in
                    Button(skin.label) { settings.petSkin = skin }
                }
            }
            Menu("兵器光效") {
                ForEach(PetWeapon.allCases) { weapon in
                    Button(weapon.label) { settings.petWeapon = weapon }
                }
            }
            Button(settings.quietMode ? "退出安静模式" : "开启安静模式") {
                settings.quietMode.toggle()
            }
            Divider()
            Button("退出桌宠") { NSApp.terminate(nil) }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.7), value: isTargeted)
        .onChange(of: events.sequence) { _ in
            showMessage(events.message, outcome: visualOutcome(for: events.outcome))
        }
        .onChange(of: isTargeted) { targeted in
            guard targeted else { return }
            receivingVariation = Int.random(in: 0..<3)
            message = PetDialogue.receiving(category: nil)
            withAnimation { messageVisible = true }
            PetSoundPlayer.play(
                outcome: .neutral,
                enabled: settings.soundEffectsEnabled,
                quietMode: settings.quietMode
            )
        }
    }

    private var isListening: Bool {
        music.isPlaying && settings.musicListeningAppearanceEnabled
    }

    private var effectiveTheme: PetTheme {
        guard settings.petTheme == .automatic else { return settings.petTheme }
        if SeasonalMoment.current() != nil, settings.seasonalEffectsEnabled { return .festive }
        return settings.petSkin == .midnight ? .night : .parchment
    }

    private var themeAccent: Color {
        switch effectiveTheme {
        case .parchment, .automatic: return Color(red: 0.91, green: 0.67, blue: 0.20)
        case .night: return Color(red: 0.35, green: 0.76, blue: 0.88)
        case .festive: return Color(red: 0.95, green: 0.31, blue: 0.22)
        }
    }

    private var messageBackground: Color {
        switch effectiveTheme {
        case .parchment, .automatic: return .black.opacity(0.76)
        case .night: return Color(red: 0.04, green: 0.08, blue: 0.18).opacity(0.86)
        case .festive: return Color(red: 0.28, green: 0.035, blue: 0.025).opacity(0.86)
        }
    }

    /// 不同状态共用轻量位移动画，避免桌面常驻角色产生过强干扰。
    private var characterYOffset: CGFloat {
        if isListening { return 0 }
        if isTargeted {
            let lift: CGFloat = receivingVariation == 1 ? -4 : 0
            return 12 + lift
        }
        switch visualState {
        case .idle: return 18
        case .receiving: return 18
        case .failure: return 20
        case .complete: return 15
        }
    }

    private var characterScale: CGFloat {
        if isListening { return 1 }
        let ambientScale: CGFloat
        if isTargeted {
            let catchScale: CGFloat = receivingVariation == 2 ? 1.018 : 1
            ambientScale = 1.025 * catchScale
        } else if visualState == .idle {
            ambientScale = 1
        } else {
            ambientScale = 1
        }
        return ambientScale * reactionScale
    }

    /// 将 Finder 拖放提供者异步转换为文件 URL，并在主线程统一整理。
    private func receive(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        // NSItemProvider 可能在多个后台队列回调，使用锁保护共享 URL 数组。
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let directURL = item as? URL {
                    url = directURL
                } else {
                    url = nil
                }
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else {
                showMessage("没接稳，再试一次", outcome: .failure)
                return
            }
            playSwordAnimation()
            visualState = .receiving
            let categories = Set(urls.map { FileOrganizer.category(for: $0) })
            let primaryCategory = categories.count == 1 ? categories.first : nil
            message = PetDialogue.receiving(category: primaryCategory)
            withAnimation { messageVisible = true }
            // 所有拖放文件作为一个批次写入历史，方便一次撤回。
            let result = FileOrganizer.organize(urls, settings: settings)
            history.record(result, source: "拖放")
            if result.movedCount > 0,
               urls.contains(where: { $0.lastPathComponent == "试拖我.txt" && $0.deletingLastPathComponent().lastPathComponent == "com.local.PetSorter-onboarding" }) {
                settings.markOnboardingSampleDropped()
            }
            if result.movedCount > 0 && result.duplicateCount > 0 {
                showMessage("收了 \(result.movedCount) 件，另有 \(result.duplicateCount) 件重复已留在原处", outcome: .complete)
            } else if result.movedCount > 0 && result.failures.isEmpty {
                showMessage(
                    PetDialogue.completed(category: primaryCategory, count: result.movedCount),
                    outcome: .complete
                )
            } else if result.movedCount > 0 {
                showMessage("收了 \(result.movedCount) 件，另有 \(result.failures.count) 件失败", outcome: .failure)
            } else if result.duplicateCount > 0 {
                showMessage("发现 \(result.duplicateCount) 件重复文件，已留在原处", outcome: .complete)
            } else {
                showMessage("未能收纳：\(result.failures.first ?? "未知错误")", outcome: .failure)
            }
        }
        return true
    }

    /// 按半数关键帧播放挥刀动作，减少透明窗口重绘和图片解码压力。
    private func playSwordAnimation() {
        guard !isPlayingSwordAnimation else { return }
        isPlayingSwordAnimation = true
        swordFrameIndex = 0
        let frameIndices = Array(stride(from: 0, to: 73, by: 2))
        let framesPerSecond = 12.0

        for (position, frameIndex) in frameIndices.dropFirst().enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(position + 1) / framesPerSecond) {
                guard isPlayingSwordAnimation else { return }
                swordFrameIndex = frameIndex
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(frameIndices.count) / framesPerSecond) {
            isPlayingSwordAnimation = false
            swordFrameIndex = 0
        }
    }

    /// 撤回历史中最近一批可恢复文件，并把部分失败情况展示给用户。
    private func undoLast() {
        guard let result = history.undoLast() else {
            showMessage("暂无可撤回的收纳", outcome: .failure)
            return
        }
        if result.failures.isEmpty {
            showMessage("已撤回 \(result.restoredCount) 件", outcome: .complete)
        } else if result.restoredCount > 0 {
            showMessage("撤回 \(result.restoredCount) 件，另有 \(result.failures.count) 件未恢复", outcome: .failure)
        } else {
            showMessage("撤回失败：\(result.failures.first ?? "未知错误")", outcome: .failure)
        }
    }

    /// 将服务层事件映射到四态视觉；普通通知保持待机姿态。
    private func visualOutcome(for outcome: PetEventOutcome) -> PetVisualState {
        switch outcome {
        case .neutral: return .idle
        case .failure: return .failure
        case .complete: return .complete
        }
    }

    /// 展示状态气泡和对应动作，结束后恢复零持续重绘的静止待机状态。
    private func showMessage(_ text: String, outcome: PetVisualState) {
        stateSequence += 1
        let currentStateSequence = stateSequence
        resultVariation = Int.random(in: 0..<3)
        visualState = outcome
        reactionOffset = 0
        reactionRotation = 0
        reactionScale = outcome == .complete ? 0.9 : 1

        if outcome == .complete {
            switch resultVariation {
            case 0:
                withAnimation(.spring(response: 0.34, dampingFraction: 0.52)) {
                    reactionScale = settings.quietMode ? 1.02 : 1.055
                }
            case 1:
                withAnimation(.spring(response: 0.38, dampingFraction: 0.58)) {
                    reactionRotation = settings.quietMode ? -1.5 : -4
                    reactionScale = settings.quietMode ? 1.01 : 1.035
                }
            default:
                withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
                    reactionOffset = settings.quietMode ? -2 : -8
                    reactionScale = settings.quietMode ? 1.01 : 1.025
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                guard currentStateSequence == stateSequence else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    reactionScale = 1
                    reactionRotation = 0
                    reactionOffset = 0
                }
            }
        } else if outcome == .failure {
            if resultVariation == 1 {
                withAnimation(.easeInOut(duration: 0.22)) {
                    reactionScale = settings.quietMode ? 0.985 : 0.95
                    reactionOffset = settings.quietMode ? 2 : 7
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                    guard currentStateSequence == stateSequence else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        reactionScale = 1
                        reactionOffset = 0
                    }
                }
            } else {
                let strength: CGFloat = settings.quietMode ? 3 : (resultVariation == 2 ? 5 : 7)
                let shake: [(Double, CGFloat, Double)] = [
                    (0.00, -strength, -1.7), (0.08, strength, 1.7),
                    (0.16, -strength * 0.7, -1.1), (0.24, strength * 0.55, 0.8), (0.32, 0, 0)
                ]
                for (delay, offset, rotation) in shake {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        guard currentStateSequence == stateSequence else { return }
                        withAnimation(.easeOut(duration: 0.08)) {
                            reactionOffset = offset
                            reactionRotation = rotation
                        }
                    }
                }
            }
        }

        PetSoundPlayer.play(
            outcome: outcome == .failure ? .failure : (outcome == .complete ? .complete : .neutral),
            enabled: settings.soundEffectsEnabled,
            quietMode: settings.quietMode
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            guard currentStateSequence == stateSequence, !isTargeted else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                visualState = .idle
                reactionScale = 1
            }
        }

        messageSequence += 1
        let currentMessageSequence = messageSequence
        message = text
        withAnimation { messageVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard currentMessageSequence == messageSequence else { return }
            withAnimation { messageVisible = false }
        }
    }
}

/// 从应用资源或开发目录读取四态桌宠立绘。
private struct StatePetArtwork: View {
    private let artwork: NSImage?

    /// 优先从打包后的 Bundle 读取资源，开发运行时回退到源码目录。
    init(state: PetVisualState, skin: PetSkin) {
        let artworkName = skin == .classic ? state.artworkName : skin.idleArtworkName
        if let url = Bundle.main.url(forResource: artworkName, withExtension: "png") {
            artwork = ArtworkCache.image(at: url)
        } else {
            let developmentURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/\(artworkName).png")
            let fallbackURL = developmentURL
                .deletingLastPathComponent()
                .appendingPathComponent("guan-yu-v2.png")
            artwork = ArtworkCache.image(at: developmentURL) ?? ArtworkCache.image(at: fallbackURL)
        }
    }

    /// 显示角色图片；资源缺失时显示醒目的错误占位图标。
    var body: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork).resizable()
            } else {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .resizable()
                    .foregroundStyle(.red)
            }
        }
    }
}

/// 读取并缓存原有的逐帧挥刀动画资源。
private struct SwordAnimationArtwork: View {
    private static let cache: NSCache<NSNumber, NSImage> = {
        let cache = NSCache<NSNumber, NSImage>()
        // 逐帧图约 0.55 MB/张，限制缓存可避免一次动作后长期占用数十 MB。
        cache.countLimit = 24
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    private let artwork: NSImage?
    private let fallbackSkin: PetSkin

    init(frameIndex: Int, fallbackSkin: PetSkin) {
        artwork = Self.load(frameIndex: frameIndex)
        self.fallbackSkin = fallbackSkin
    }

    private static func load(frameIndex: Int) -> NSImage? {
        let key = NSNumber(value: frameIndex)
        if let cached = cache.object(forKey: key) { return cached }

        let name = String(format: "frame-%03d", frameIndex + 1)
        let packagedURL = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "sword-animation"
        )
        let developmentURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/sword-animation/\(name).png")
        let image = NSImage(contentsOf: packagedURL ?? developmentURL)
        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            cache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    var body: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork).resizable()
            } else {
                PetArtwork(skin: fallbackSkin)
            }
        }
    }
}

/// 设置页与首次引导沿用待机形象，不参与桌宠状态切换。
struct PetArtwork: View {
    var skin: PetSkin = .classic

    var body: some View {
        StatePetArtwork(state: .idle, skin: skin)
    }
}

/// 主题氛围使用透明径向光，不增加桌宠窗口的实色背景。
private struct ThemeAura: View {
    let theme: PetTheme

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [accent.opacity(0.08), .clear],
                    center: .center,
                    startRadius: 12,
                    endRadius: 132
                )
            )
            .frame(width: 264, height: 264)
            .scaleEffect(0.99)
            .offset(y: 18)
    }

    private var accent: Color {
        switch theme {
        case .parchment, .automatic: return Color(red: 0.93, green: 0.67, blue: 0.18)
        case .night: return Color(red: 0.22, green: 0.62, blue: 0.86)
        case .festive: return Color(red: 0.95, green: 0.22, blue: 0.16)
        }
    }
}

/// 用光刃和徽记区分兵器款式，同时保持原始角色轮廓与拖放热区稳定。
private struct WeaponAura: View {
    let weapon: PetWeapon

    var body: some View {
        ZStack {
            Capsule()
                .fill(color.opacity(0.14))
                .frame(width: 8, height: 122)
                .blur(radius: 5)
                .rotationEffect(.degrees(-43))
                .offset(x: -68, y: -27)
            Image(systemName: weapon.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color.opacity(0.9))
                .padding(6)
                .background(.black.opacity(0.48), in: Circle())
                .offset(x: -94, y: -89)
        }
        .shadow(color: color.opacity(0.42), radius: 4)
    }

    private var color: Color {
        switch weapon {
        case .greenDragon: return Color(red: 0.24, green: 0.78, blue: 0.45)
        case .ember: return Color(red: 1.0, green: 0.34, blue: 0.10)
        case .frost: return Color(red: 0.35, green: 0.82, blue: 1.0)
        }
    }
}
