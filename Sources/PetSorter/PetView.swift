import SwiftUI
import UniformTypeIdentifiers

/// 展示可拖动、可接收 Finder 文件的关羽桌宠主界面。
struct PetView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var history: OperationHistoryStore
    @ObservedObject var events: PetEventStore
    let openSettings: () -> Void
    let patrolNow: () -> Void

    @State private var isTargeted = false
    @State private var videoFrameIndex = 0
    @State private var message = "把文件交给关将军"
    @State private var messageVisible = true
    @State private var isAnimating = false

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

            Group {
                if isAnimating {
                    SwordAnimationArtwork(frameIndex: videoFrameIndex)
                } else {
                    PetArtwork()
                }
            }
                .scaledToFit()
                .frame(width: 245, height: 275)
                .offset(y: 18)
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
            DispatchQueue.global(qos: .utility).async {
                SwordAnimationArtwork.preload()
            }
        }
        .onChange(of: events.sequence) { _ in
            playSwordAnimation()
            showMessage(events.message)
        }
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
                showMessage("没接稳，再试一次")
                return
            }
            playSwordAnimation()
            // 所有拖放文件作为一个批次写入历史，方便一次撤回。
            let result = FileOrganizer.organize(urls, settings: settings)
            history.record(result, source: "拖放")
            if result.movedCount > 0,
               urls.contains(where: { $0.lastPathComponent == "试拖我.txt" && $0.deletingLastPathComponent().lastPathComponent == "com.local.PetSorter-onboarding" }) {
                settings.markOnboardingSampleDropped()
            }
            if result.movedCount > 0 && result.duplicateCount > 0 {
                showMessage("收了 \(result.movedCount) 件，另有 \(result.duplicateCount) 件重复已留在原处")
            } else if result.movedCount > 0 && result.failures.isEmpty {
                showMessage("收了 \(result.movedCount) 件！已归入\(result.categoryNames.joined(separator: "、"))")
            } else if result.movedCount > 0 {
                showMessage("收了 \(result.movedCount) 件，另有 \(result.failures.count) 件失败")
            } else if result.duplicateCount > 0 {
                showMessage("发现 \(result.duplicateCount) 件重复文件，已留在原处")
            } else {
                showMessage("未能收纳：\(result.failures.first ?? "未知错误")")
            }
        }
        return true
    }

    /// 撤回历史中最近一批可恢复文件，并把部分失败情况展示给用户。
    private func undoLast() {
        guard let result = history.undoLast() else {
            showMessage("暂无可撤回的收纳")
            return
        }
        if result.failures.isEmpty {
            showMessage("已撤回 \(result.restoredCount) 件")
        } else if result.restoredCount > 0 {
            showMessage("撤回 \(result.restoredCount) 件，另有 \(result.failures.count) 件未恢复")
        } else {
            showMessage("撤回失败：\(result.failures.first ?? "未知错误")")
        }
    }

    /// 以 18 FPS 播放 73 帧挥刀序列，并在结束后恢复待机图。
    private func playSwordAnimation() {
        guard !isAnimating else { return }
        isAnimating = true
        videoFrameIndex = 0
        let frameCount = 73
        let framesPerSecond = 18.0

        for index in 1..<frameCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) / framesPerSecond) {
                guard isAnimating else { return }
                videoFrameIndex = index
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(frameCount) / framesPerSecond) {
            isAnimating = false
            videoFrameIndex = 0
        }
    }

    /// 展示状态气泡，并在四秒后使用动画自动隐藏。
    private func showMessage(_ text: String) {
        message = text
        withAnimation { messageVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { messageVisible = false }
        }
    }
}

/// 从应用资源或开发目录读取桌宠待机图。
struct PetArtwork: View {
    private let artwork: NSImage?

    /// 优先从打包后的 Bundle 读取资源，开发运行时回退到源码目录。
    init() {
        if let url = Bundle.main.url(forResource: "guan-yu-v2", withExtension: "png") {
            artwork = NSImage(contentsOf: url)
        } else {
            let developmentURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/guan-yu-v2.png")
            artwork = NSImage(contentsOf: developmentURL)
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

/// 读取并缓存逐帧挥刀动画资源。
private struct SwordAnimationArtwork: View {
    private static let cache: NSCache<NSNumber, NSImage> = {
        let cache = NSCache<NSNumber, NSImage>()
        cache.countLimit = 73
        return cache
    }()
    private let artwork: NSImage?

    /// 读取指定索引对应的动画帧。
    init(frameIndex: Int) {
        artwork = Self.load(frameIndex: frameIndex)
    }

    /// 在后台提前装载全部帧，避免首次拖放时逐帧卡顿。
    static func preload() {
        for index in 0..<73 { _ = load(frameIndex: index) }
    }

    /// 从内存缓存、应用 Bundle 或开发目录依次寻找指定帧。
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

    /// 显示当前动画帧；资源缺失时回退到待机图。
    var body: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork).resizable()
            } else {
                PetArtwork()
            }
        }
    }
}
