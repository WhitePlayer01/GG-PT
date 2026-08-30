import SwiftUI
import UniformTypeIdentifiers
import Combine

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
    let openSettings: () -> Void
    let patrolNow: () -> Void

    @State private var isTargeted = false
    @State private var swordFrameIndex = 0
    @State private var isPlayingSwordAnimation = false
    @State private var message = "把文件交给关将军"
    @State private var messageVisible = true
    @State private var visualState: PetVisualState = .idle
    @State private var ambientMotion = false
    @State private var reactionOffset: CGFloat = 0
    @State private var reactionRotation = 0.0
    @State private var reactionScale: CGFloat = 1
    @State private var stateSequence = 0
    @State private var messageSequence = 0
    @State private var idleVariation = 0
    @State private var receivingVariation = 0
    @State private var resultVariation = 0
    @State private var seasonalMotion = false

    private static let idleTimer = Timer.publish(every: 9, on: .main, in: .common).autoconnect()

    /// 组合投放高亮、角色动画、设置入口和结果消息气泡。
    var body: some View {
        ZStack {
            ThemeAura(theme: effectiveTheme, pulse: ambientMotion)

            if settings.seasonalEffectsEnabled, let moment = SeasonalMoment.current() {
                Image(systemName: moment.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(themeAccent.opacity(settings.quietMode ? 0.28 : 0.72))
                    .rotationEffect(.degrees(seasonalMotion ? 10 : -10))
                    .offset(x: seasonalMotion ? 92 : 82, y: seasonalMotion ? -78 : -65)
                    .shadow(color: themeAccent.opacity(0.35), radius: 6)
                    .accessibilityLabel(moment.name)
            }

            WeaponAura(weapon: settings.petWeapon, pulse: ambientMotion)

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
                    .stroke(themeAccent.opacity(ambientMotion ? 0.08 : 0.48), lineWidth: 4)
                    .frame(width: ambientMotion ? 260 : 205, height: ambientMotion ? 260 : 205)
                    .scaleEffect(ambientMotion ? 1.06 : 0.88)
                    .transition(.scale.combined(with: .opacity))
            } else if visualState == .failure && !isTargeted {
                Circle()
                    .fill(Color.red.opacity(ambientMotion ? 0.05 : 0.14))
                    .frame(width: 225, height: 225)
                    .scaleEffect(ambientMotion ? 1.04 : 0.94)
                    .transition(.opacity)
            }

            Group {
                if isPlayingSwordAnimation {
                    SwordAnimationArtwork(frameIndex: swordFrameIndex, fallbackSkin: settings.petSkin)
                } else {
                    StatePetArtwork(state: isTargeted ? .receiving : visualState, skin: settings.petSkin)
                }
            }
                .scaledToFit()
                .frame(width: 245, height: 275)
                .scaleEffect(characterScale, anchor: .bottom)
                .rotationEffect(.degrees(reactionRotation), anchor: .bottom)
                .offset(x: reactionOffset, y: characterYOffset)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 4)

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
                if messageVisible {
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

            if settings.showsDailyBadge, !messageVisible {
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
        .onAppear {
            DispatchQueue.global(qos: .utility).async {
                SwordAnimationArtwork.preload()
            }
            withAnimation(.easeInOut(duration: 1.65).repeatForever(autoreverses: true)) {
                ambientMotion = true
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                seasonalMotion = true
            }
        }
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
        .onReceive(Self.idleTimer) { _ in
            playIdleVariation()
        }
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
        if isTargeted {
            let lift: CGFloat = receivingVariation == 1 ? -4 : 0
            return (ambientMotion ? 10 : 15) + lift
        }
        switch visualState {
        case .idle: return ambientMotion ? 16 : 20
        case .receiving: return 18
        case .failure: return ambientMotion ? 19 : 21
        case .complete: return ambientMotion ? 13 : 18
        }
    }

    private var characterScale: CGFloat {
        let ambientScale: CGFloat
        if isTargeted {
            let catchScale: CGFloat = receivingVariation == 2 ? 1.018 : 1
            ambientScale = (ambientMotion ? 1.035 : 1.01) * catchScale
        } else if visualState == .idle {
            ambientScale = ambientMotion ? 1.008 : 0.996
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

    /// 恢复原有的 73 帧挥刀动画，每次成功接收 Finder 投放后播放一次。
    private func playSwordAnimation() {
        guard !isPlayingSwordAnimation else { return }
        isPlayingSwordAnimation = true
        swordFrameIndex = 0
        let frameCount = 73
        let framesPerSecond = 18.0

        for index in 1..<frameCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) / framesPerSecond) {
                guard isPlayingSwordAnimation else { return }
                swordFrameIndex = index
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(frameCount) / framesPerSecond) {
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

    /// 展示状态气泡和对应动作，结束后恢复低干扰待机循环。
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

    /// 待机时轮换呼吸、侧听和轻点刀柄三种低幅动作。
    private func playIdleVariation() {
        guard visualState == .idle, !isTargeted, !settings.quietMode else { return }
        idleVariation = (idleVariation + 1) % 3
        let currentSequence = stateSequence
        switch idleVariation {
        case 1:
            withAnimation(.easeInOut(duration: 0.35)) { reactionRotation = -1.8 }
        case 2:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) {
                reactionOffset = -4
                reactionScale = 1.012
            }
        default:
            withAnimation(.easeInOut(duration: 0.42)) { reactionScale = 1.018 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard currentSequence == stateSequence, visualState == .idle else { return }
            withAnimation(.easeInOut(duration: 0.36)) {
                reactionRotation = 0
                reactionOffset = 0
                reactionScale = 1
            }
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
            artwork = NSImage(contentsOf: url)
        } else {
            let developmentURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/\(artworkName).png")
            let fallbackURL = developmentURL
                .deletingLastPathComponent()
                .appendingPathComponent("guan-yu-v2.png")
            artwork = NSImage(contentsOf: developmentURL) ?? NSImage(contentsOf: fallbackURL)
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
        cache.countLimit = 73
        return cache
    }()

    private let artwork: NSImage?
    private let fallbackSkin: PetSkin

    init(frameIndex: Int, fallbackSkin: PetSkin) {
        artwork = Self.load(frameIndex: frameIndex)
        self.fallbackSkin = fallbackSkin
    }

    /// 在后台预载全部帧，避免首次拖放时卡顿。
    static func preload() {
        for index in 0..<73 { _ = load(frameIndex: index) }
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
        if let image { cache.setObject(image, forKey: key) }
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
    let pulse: Bool

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [accent.opacity(pulse ? 0.13 : 0.06), .clear],
                    center: .center,
                    startRadius: 12,
                    endRadius: 132
                )
            )
            .frame(width: 264, height: 264)
            .scaleEffect(pulse ? 1.03 : 0.96)
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
    let pulse: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(color.opacity(pulse ? 0.22 : 0.10))
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
        .shadow(color: color.opacity(0.5), radius: pulse ? 8 : 4)
    }

    private var color: Color {
        switch weapon {
        case .greenDragon: return Color(red: 0.24, green: 0.78, blue: 0.45)
        case .ember: return Color(red: 1.0, green: 0.34, blue: 0.10)
        case .frost: return Color(red: 0.35, green: 0.82, blue: 1.0)
        }
    }
}
