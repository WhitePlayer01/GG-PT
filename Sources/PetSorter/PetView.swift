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
    let openSettings: () -> Void
    let patrolNow: () -> Void

    @State private var isTargeted = false
    @State private var message = "把文件交给关将军"
    @State private var messageVisible = true
    @State private var visualState: PetVisualState = .idle
    @State private var ambientMotion = false
    @State private var reactionOffset: CGFloat = 0
    @State private var reactionRotation = 0.0
    @State private var reactionScale: CGFloat = 1
    @State private var stateSequence = 0
    @State private var messageSequence = 0

    /// 组合投放高亮、角色动画、设置入口和结果消息气泡。
    var body: some View {
        ZStack {
            if isTargeted {
                // 文件悬停时显示金色接收区域，提示当前可以松手投放。
                Circle()
                    .fill(Color.yellow.opacity(0.16))
                    .overlay(Circle().stroke(Color.yellow.opacity(0.85), lineWidth: 3))
                    .frame(width: 250, height: 250)
                    .blur(radius: 0.3)
                    .transition(.scale.combined(with: .opacity))
            }

            if visualState == .complete && !isTargeted {
                Circle()
                    .stroke(Color.yellow.opacity(ambientMotion ? 0.08 : 0.48), lineWidth: 4)
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

            StatePetArtwork(state: isTargeted ? .receiving : visualState)
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
                        .background(.black.opacity(0.72), in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(10)
        }
        .frame(width: 270, height: 330)
        .scaleEffect(settings.petScale, anchor: .bottom)
        .frame(width: 270 * settings.petScale, height: 330 * settings.petScale)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: receive(providers:))
        .contextMenu {
            Button("收纳设置…", action: openSettings)
            Button("打开收纳箱", action: settings.revealBaseDirectory)
            Button("立即巡查桌面与下载", action: patrolNow)
                .disabled(!settings.monitorDesktop && !settings.monitorDownloads)
            Button("撤回上次收纳", action: undoLast)
                .disabled(!history.canUndo)
            Divider()
            Button("退出桌宠") { NSApp.terminate(nil) }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.7), value: isTargeted)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.65).repeatForever(autoreverses: true)) {
                ambientMotion = true
            }
        }
        .onChange(of: events.sequence) { _ in
            showMessage(events.message, outcome: inferredOutcome(for: events.message))
        }
    }

    /// 不同状态共用轻量位移动画，避免桌面常驻角色产生过强干扰。
    private var characterYOffset: CGFloat {
        if isTargeted { return ambientMotion ? 10 : 15 }
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
            ambientScale = ambientMotion ? 1.035 : 1.01
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
            visualState = .receiving
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
                showMessage("收了 \(result.movedCount) 件！已归入\(result.categoryNames.joined(separator: "、"))", outcome: .complete)
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

    /// 跨服务消息没有显式状态时，按稳定关键词选择完成或失败反馈。
    private func inferredOutcome(for text: String) -> PetVisualState {
        let failureWords = ["失败", "未能", "未完成", "没接稳", "错误"]
        return failureWords.contains(where: text.contains) ? .failure : .complete
    }

    /// 展示状态气泡和对应动作，结束后恢复低干扰待机循环。
    private func showMessage(_ text: String, outcome: PetVisualState) {
        stateSequence += 1
        let currentStateSequence = stateSequence
        visualState = outcome
        reactionOffset = 0
        reactionRotation = 0
        reactionScale = outcome == .complete ? 0.9 : 1

        if outcome == .complete {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.52)) {
                reactionScale = 1.055
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                guard currentStateSequence == stateSequence else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    reactionScale = 1
                }
            }
        } else {
            let shake: [(Double, CGFloat, Double)] = [
                (0.00, -7, -2.0), (0.08, 7, 2.0), (0.16, -5, -1.4),
                (0.24, 4, 1.0), (0.32, 0, 0)
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
    init(state: PetVisualState) {
        if let url = Bundle.main.url(forResource: state.artworkName, withExtension: "png") {
            artwork = NSImage(contentsOf: url)
        } else {
            let developmentURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/\(state.artworkName).png")
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

/// 设置页与首次引导沿用待机形象，不参与桌宠状态切换。
struct PetArtwork: View {
    var body: some View {
        StatePetArtwork(state: .idle)
    }
}
