import SwiftUI
import UniformTypeIdentifiers

struct PetView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var history: OperationHistoryStore
    @ObservedObject var events: PetEventStore
    let openSettings: () -> Void

    @State private var isTargeted = false
    @State private var videoFrameIndex = 0
    @State private var message = "把文件交给关将军"
    @State private var messageVisible = true
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            if isTargeted {
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

    private func receive(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

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
            let result = FileOrganizer.organize(urls, settings: settings)
            history.record(result, source: "拖放")
            if result.failures.isEmpty {
                showMessage("收了 \(result.movedCount) 件！已归入\(result.categoryNames.joined(separator: "、"))")
            } else if result.movedCount > 0 {
                showMessage("收了 \(result.movedCount) 件，另有 \(result.failures.count) 件失败")
            } else {
                showMessage("未能收纳：\(result.failures.first ?? "未知错误")")
            }
        }
        return true
    }

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

    private func showMessage(_ text: String) {
        message = text
        withAnimation { messageVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { messageVisible = false }
        }
    }
}

struct PetArtwork: View {
    private let artwork: NSImage?

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

private struct SwordAnimationArtwork: View {
    private static let cache: NSCache<NSNumber, NSImage> = {
        let cache = NSCache<NSNumber, NSImage>()
        cache.countLimit = 73
        return cache
    }()
    private let artwork: NSImage?

    init(frameIndex: Int) {
        artwork = Self.load(frameIndex: frameIndex)
    }

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
                PetArtwork()
            }
        }
    }
}
