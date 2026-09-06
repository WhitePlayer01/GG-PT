import AppKit
import AVFoundation
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// 视频保留压缩文件，避免长动画展开成大量图片占用内存。
struct VideoArtwork: Codable, Equatable {
    let fileExtension: String
    let duration: Double
    var isValid: Bool {
        ["mov", "mp4"].contains(fileExtension) && duration.isFinite && duration > 0 && duration <= 120
    }
}

/* 只在后台读取用户选择的本机视频，验证首帧后复制原文件。
 失败时清除此轮新建目录，不修改已保存的方案或原始素材。 */
enum VideoArtworkImporter {
    static func importVideo(from url: URL, root: URL) async throws -> CustomArtwork {
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard info.isRegularFile == true, let size = info.fileSize, size <= 64 * 1024 * 1024 else {
            throw ArtworkImporter.failure("请选择不超过 64 MB 的 MOV 或 MP4 视频。")
        }
        let source = AVURLAsset(url: url)
        let duration = try await source.load(.duration).seconds
        let video = VideoArtwork(fileExtension: url.pathExtension.lowercased(), duration: duration)
        let protected = try await source.load(.hasProtectedContent)
        let tracks = try await source.loadTracks(withMediaType: .video)
        guard video.isValid, !protected, let track = tracks.first else {
            throw ArtworkImporter.failure("视频无法读取、没有画面或超过 120 秒，请选择其他 MOV / MP4 文件。")
        }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let dimensions = naturalSize.applying(transform)
        guard dimensions.width.isFinite, dimensions.height.isFinite,
              abs(dimensions.width) > 0, abs(dimensions.height) > 0,
              abs(dimensions.width) <= 4096, abs(dimensions.height) <= 4096 else {
            throw ArtworkImporter.failure("视频画面尺寸不能超过 4096 × 4096。")
        }
        let generator = AVAssetImageGenerator(asset: source)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 768, height: 768)
        let poster: CGImage
        do { poster = try await generator.image(at: .zero).image }
        catch { throw ArtworkImporter.failure("无法解码视频画面，请使用系统支持的编码（如 H.264 或 HEVC）。") }
        let id = UUID().uuidString
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: directory) } }
        try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent("video.\(video.fileExtension)"))
        let posterURL = directory.appendingPathComponent("0.png")
        guard let destination = CGImageDestinationCreateWithURL(posterURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ArtworkImporter.failure("无法保存视频预览。")
        }
        CGImageDestinationAddImage(destination, poster, nil)
        guard CGImageDestinationFinalize(destination) else { throw ArtworkImporter.failure("视频预览保存失败。") }
        succeeded = true
        // 首帧供减少动态效果和未播放时预览使用，时长由视频元数据提供。
        return CustomArtwork(directory: id, name: url.lastPathComponent, durations: [0.1],
                             preservesMotion: false, video: video)
    }
}

/* 原生视频图层没有播放控件，不抢占桌宠拖放交互。播放器永远静音，
 一次性场景停在末帧，循环场景到末尾后重播；离开视图立即释放播放器。 */
struct VideoArtworkPlayer: NSViewRepresentable {
    let url: URL
    var playing: Bool
    var loops: Bool
    var onFailure: (String) -> Void

    final class Surface: NSView {
        let videoLayer = AVPlayerLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            videoLayer.videoGravity = .resizeAspect
            videoLayer.backgroundColor = NSColor.clear.cgColor
            layer?.addSublayer(videoLayer)
        }
        required init?(coder: NSCoder) { fatalError("不支持从归档创建视频视图") }
        override func layout() { super.layout(); videoLayer.frame = bounds }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    final class Coordinator {
        let player = AVPlayer()
        var url: URL?
        var playing = false
        var loops = false
        var ended = false
        var status: NSKeyValueObservation?
        var endToken: NSObjectProtocol?
        var failureToken: NSObjectProtocol?
        var onFailure: (String) -> Void = { _ in }

        func configure(url: URL) {
            guard self.url != url else { updatePlayback(); return }
            clear()
            self.url = url
            guard FileManager.default.fileExists(atPath: url.path) else {
                reportFailure("视频副本缺失，请重新导入。")
                return
            }
            let item = AVPlayerItem(url: url)
            player.isMuted = true
            player.actionAtItemEnd = .pause
            player.replaceCurrentItem(with: item)
            status = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
                DispatchQueue.main.async {
                    guard let self, let item, self.player.currentItem === item else { return }
                    if item.status == .failed { self.reportFailure("视频播放失败，请重新导入系统支持的视频编码。") }
                    else if item.status == .readyToPlay { self.updatePlayback() }
                }
            }
            endToken = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.ended = true
                self.updatePlayback()
            }
            failureToken = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                self?.reportFailure("视频未能完整播放，请重新导入。")
            }
            updatePlayback()
        }

        func updatePlayback() {
            guard playing, player.currentItem?.status == .readyToPlay else { player.pause(); return }
            if ended {
                guard loops else { return }
                ended = false
                let item = player.currentItem
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                    DispatchQueue.main.async {
                        guard let self, finished, self.playing, self.player.currentItem === item else { return }
                        self.player.play()
                    }
                }
            } else if player.rate == 0 { player.play() }
        }

        func reportFailure(_ message: String) {
            player.pause()
            // SwiftUI 更新过程中不能直接修改错误状态，排到下一轮主线程。
            let failedURL = url
            DispatchQueue.main.async { [weak self] in
                guard let self, self.url == failedURL else { return }
                self.onFailure(message)
            }
        }
        func clear() {
            status?.invalidate(); status = nil
            if let endToken { NotificationCenter.default.removeObserver(endToken) }
            if let failureToken { NotificationCenter.default.removeObserver(failureToken) }
            endToken = nil; failureToken = nil
            player.pause(); player.replaceCurrentItem(with: nil)
            url = nil; ended = false
        }
        deinit { clear() }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> Surface {
        let view = Surface(frame: .zero)
        view.videoLayer.player = context.coordinator.player
        return view
    }
    func updateNSView(_ view: Surface, context: Context) {
        context.coordinator.playing = playing
        context.coordinator.loops = loops
        context.coordinator.onFailure = onFailure
        context.coordinator.configure(url: url)
    }
    static func dismantleNSView(_ view: Surface, coordinator: Coordinator) {
        coordinator.clear()
        view.videoLayer.player = nil
    }
}
