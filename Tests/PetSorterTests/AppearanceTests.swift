import Foundation
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/* 用内存偏好验证方案迁移和重启读取，不修改用户真实设置。
 所有素材测试均在系统临时目录下完成，并在退出时清理。 */
final class AppearanceTestDefaults: UserDefaults {
    var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
    override func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
}

@main
struct AppearanceTests {
    @MainActor static func main() async throws {
        let defaults = AppearanceTestDefaults()
        defaults.set(0.7, forKey: "petOpacity")
        let settings = SettingsStore(defaults: defaults)
        precondition(settings.appearanceLibrary.profiles.count == 3)
        precondition(settings.appearanceLibrary.profiles[0].opacity == 0.7, "升级应保留旧设置")
        var library = settings.appearanceLibrary
        library.profiles[1].name = "试验方案"
        library.profiles[1].opacity = 0.55
        library.profiles[1].isConfigured = true
        precondition(settings.saveAppearance(library))
        precondition(settings.petOpacity == 0.7, "保存未启用方案不能改变当前透明度")
        library.activeIndex = 1
        precondition(settings.saveAppearance(library))
        precondition(settings.petOpacity == 0.55)
        let restored = SettingsStore(defaults: defaults)
        precondition(restored.appearanceLibrary == library, "重建设置对象应完整恢复三套方案")
        restored.updateCurrentAppearance(quiet: true)
        precondition(restored.appearanceLibrary.profiles[1].quiet)
        let goodData = defaults.data(forKey: "appearanceLibrary")!
        var invalid = library; invalid.profiles.removeLast()
        precondition(!settings.saveAppearance(invalid), "不能保存少于三套的异常配置")
        precondition(defaults.data(forKey: "appearanceLibrary") == goodData)
        defaults.set(Data("invalid".utf8), forKey: "appearanceLibrary")
        let corrupt = SettingsStore(defaults: defaults)
        precondition(!corrupt.appearanceError.isEmpty)
        precondition(!corrupt.saveAppearance(library), "损坏配置不能被静默覆盖")
        precondition(defaults.data(forKey: "appearanceLibrary") == Data("invalid".utf8))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("appearance-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed")
        let image = makeImage()
        let png = root.appendingPathComponent("source.png")
        try write(image, to: png, type: .png)
        let imported = try await ArtworkImporter.importArtwork(from: png, root: managed)
        precondition(!imported.isAnimated && imported.preservesMotion)
        let loaded = try ArtworkImporter.loadFrames(imported, root: managed)
        precondition(loaded.count == 1 && loaded[0].width == 12)
        try FileManager.default.removeItem(at: png)
        precondition(FileManager.default.fileExists(atPath: managed.appendingPathComponent(imported.directory).appendingPathComponent("0.png").path), "删除原图不应影响副本")
        let sequence = root.appendingPathComponent("sequence")
        try FileManager.default.createDirectory(at: sequence, withIntermediateDirectories: true)
        try write(image, to: sequence.appendingPathComponent("frame-2.png"), type: .png)
        try write(image, to: sequence.appendingPathComponent("frame-10.png"), type: .png)
        let frames = try await ArtworkImporter.importArtwork(from: sequence, root: managed)
        precondition(frames.durations.count == 2 && frames.isAnimated && !frames.preservesMotion)
        precondition(abs(frames.duration - 2.0 / 12) < 0.001)
        /* 按需解码不能读取相邻帧；缺失帧和越界请求必须明确失败。 */
        let frameURL = managed.appendingPathComponent(frames.directory).appendingPathComponent("1.png")
        let savedFrame = try Data(contentsOf: frameURL)
        try FileManager.default.removeItem(at: frameURL)
        let firstFrame = try ArtworkImporter.loadFrame(frames, index: 0, root: managed)
        precondition(firstFrame.width == 12) // 第二帧缺失也不影响第一帧。
        for index in [-1, 1, 2] {
            do {
                _ = try ArtworkImporter.loadFrame(frames, index: index, root: managed)
                preconditionFailure("缺失或越界帧应失败")
            } catch { precondition((error as NSError).domain == "CustomArtwork") }
        }
        try savedFrame.write(to: frameURL)
        /* 用已删除的磁盘帧检查缓存命中及六帧淘汰，不依赖内存估算。 */
        let cacheAsset = CustomArtwork(directory: UUID().uuidString, name: "缓存测试",
                                       durations: Array(repeating: 0.1, count: 7), preservesMotion: false)
        let cacheDirectory = managed.appendingPathComponent(cacheAsset.directory)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        for index in 0..<7 { try write(image, to: cacheDirectory.appendingPathComponent("\(index).png"), type: .png) }
        let loader = ArtworkFrameLoader(root: managed)
        _ = try await loader.image(cacheAsset, index: 0)
        try FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent("0.png"))
        _ = try await loader.image(cacheAsset, index: 0) // 命中缓存，不重复读盘。
        for index in 1..<7 { _ = try await loader.image(cacheAsset, index: index) }
        do {
            _ = try await loader.image(cacheAsset, index: 0)
            preconditionFailure("第七帧应淘汰最早缓存")
        } catch { precondition((error as NSError).domain == "CustomArtwork") }
        let gif = root.appendingPathComponent("loop.gif")
        let destination = CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, 2, nil)!
        for delay in [0.1, 0.2] {
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        precondition(CGImageDestinationFinalize(destination))
        let animation = try await ArtworkImporter.importArtwork(from: gif, root: managed)
        precondition(animation.durations.count == 2)
        precondition(abs(animation.duration - 0.3) < 0.001)
        precondition(animation.frameIndex(at: 0.15, loops: true) == 1)
        precondition(animation.frameIndex(at: 0.35, loops: true) == 0)
        precondition(animation.frameIndex(at: 99, loops: false) == 1)
        precondition(animation.frameIndex(at: -1, loops: false) == 0)
        let assetObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(animation))
        let legacyObject: [String: Any] = ["skin": "midnight", "theme": "night", "weapon": "frost",
                                            "artworks": ["midnight/sword": assetObject]]
        let legacy = try JSONDecoder().decode(AppearanceProfile.self,
            from: JSONSerialization.data(withJSONObject: legacyObject))
        precondition(legacy.artworks[ArtworkScene.sword.key()] == animation,
                     "移除旧功能后应保留已导入素材")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        precondition(encoded["skin"] == nil && encoded["weapon"] == nil && encoded["theme"] == nil,
                     "新配置不能再保存已删除功能的字段")
        let roundTrip = try JSONDecoder().decode(AppearanceProfile.self, from: JSONEncoder().encode(legacy))
        precondition(roundTrip == legacy, "新格式素材键应能再次读取")
        var copied = library.profiles[1]
        copied.artworks[ArtworkScene.listening.key(variant: .nod)] = animation
        library.profiles[2] = copied
        copied.artworks.removeAll()
        precondition(library.profiles[2].artworks.count == 1, "修改副本不能修改其他槽位")
        precondition(ArtworkScene.listening.key(variant: .sway) != ArtworkScene.listening.key(variant: .nod))
        precondition(ArtworkScene.receiving.key() == ArtworkScene.sword.key(), "接收必须共用挥刀素材")
        precondition(!ArtworkScene.receiving.loops && !ArtworkScene.sword.loops, "接收与挥刀均播放一次")
        let bad = root.appendingPathComponent("bad.png")
        try Data("not an image".utf8).write(to: bad)
        let before = try FileManager.default.contentsOfDirectory(atPath: managed.path).count
        do {
            _ = try await ArtworkImporter.importArtwork(from: bad, root: managed)
            fatalError("损坏文件必须被拒绝")
        } catch {}
        let after = try FileManager.default.contentsOfDirectory(atPath: managed.path).count
        precondition(after == before, "失败导入不得留下半成品")
        for fileType: AVFileType in [.mov, .mp4] {
            let ext = fileType == .mov ? "mov" : "mp4"
            let url = root.appendingPathComponent("sample.\(ext)")
            try await makeVideo(at: url, type: fileType)
            let clip = try await ArtworkImporter.importArtwork(from: url, root: managed)
            precondition(clip.video?.fileExtension == ext && clip.isAnimated && !clip.preservesMotion)
            precondition(clip.duration > 0.5 && clip.duration <= 1.1)
            let poster = try ArtworkImporter.loadFrames(clip, root: managed)
            precondition(poster.count == 1)
            let restoredClip = try JSONDecoder().decode(CustomArtwork.self, from: JSONEncoder().encode(clip))
            precondition(restoredClip == clip)
            try FileManager.default.removeItem(at: url)
            let copyURL = managed.appendingPathComponent(clip.directory).appendingPathComponent("video.\(ext)")
            precondition(FileManager.default.fileExists(atPath: copyURL.path), "视频副本应独立于原文件")
            let player = AVPlayer(url: copyURL)
            player.isMuted = true
            let item = player.currentItem!
            let deadline = Date().addingTimeInterval(8)
            while item.status == .unknown && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
            precondition(item.status == .readyToPlay, "导入的视频应可供原生播放器读取")
            player.replaceCurrentItem(with: nil)
            let coordinator = VideoArtworkPlayer.Coordinator()
            var playbackError = ""
            coordinator.onFailure = { playbackError = $0 }
            coordinator.playing = true
            coordinator.configure(url: copyURL)
            let playingDeadline = Date().addingTimeInterval(8)
            while coordinator.player.currentTime().seconds < 0.15 && Date() < playingDeadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            precondition(playbackError.isEmpty && coordinator.player.currentTime().seconds >= 0.15,
                         "原生视频应实际推进播放进度")
            precondition(coordinator.player.isMuted, "素材播放必须静音")
            coordinator.playing = false
            coordinator.updatePlayback()
            let pausedTime = coordinator.player.currentTime().seconds
            try await Task.sleep(nanoseconds: 150_000_000)
            precondition(abs(coordinator.player.currentTime().seconds - pausedTime) < 0.08, "暂停后进度应停止")
            coordinator.playing = true
            coordinator.updatePlayback()
            let endDeadline = Date().addingTimeInterval(4)
            while !coordinator.ended && Date() < endDeadline { try await Task.sleep(nanoseconds: 50_000_000) }
            precondition(coordinator.ended && coordinator.player.rate == 0, "一次性场景结束后应停止")
            coordinator.loops = true
            coordinator.updatePlayback()
            let loopDeadline = Date().addingTimeInterval(4)
            while (coordinator.player.currentTime().seconds >= 0.9 || coordinator.player.currentTime().seconds < 0.1) && Date() < loopDeadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            precondition(!coordinator.ended && coordinator.player.currentTime().seconds < 0.9 && coordinator.player.rate > 0,
                         "循环场景应从头继续播放")
            coordinator.clear()
            precondition(coordinator.player.currentItem == nil && coordinator.status == nil && coordinator.endToken == nil,
                         "离开视图应释放媒体与观察器")
        }
        let badVideo = root.appendingPathComponent("bad.mp4")
        try Data("not a video".utf8).write(to: badVideo)
        do {
            _ = try await ArtworkImporter.importArtwork(from: badVideo, root: managed)
            fatalError("损坏视频必须被拒绝")
        } catch {}
        precondition(!VideoArtwork(fileExtension: "mp4", duration: .infinity).isValid)
        precondition(!VideoArtwork(fileExtension: "mov", duration: 121).isValid)
        precondition(!VideoArtwork(fileExtension: "avi", duration: 1).isValid)
        print("通过：三槽位迁移、独立保存、激活、恢复读取、快捷设置同步、损坏保护、PNG/GIF/序列/MOV/MP4 导入与原生播放校验、源文件独立、播放边界、旧配置迁移/听歌动作隔离、失败清理")
    }

    /* 使用软件编码器生成一秒钟的测试视频，不依赖测试进程能否访问硬件编码服务。
     只在系统临时目录生成素材，测试结束统一清理。 */
    static func makeVideo(at url: URL, type: AVFileType) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        process.arguments = ["-v", "error", "-f", "lavfi", "-i", "color=c=green:s=32x32:r=12:d=1",
                             "-c:v", "libx264", "-pix_fmt", "yuv420p", "-an", url.path]
        try process.run()
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        guard !process.isRunning else { process.terminate(); throw ArtworkImporter.failure("测试视频生成超时") }
        guard process.terminationStatus == 0 else { throw ArtworkImporter.failure("测试视频生成失败") }
    }

    // 生成小型测试图，避免测试依赖真实用户素材。
    static func makeImage() -> CGImage {
        let context = CGContext(data: nil, width: 12, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 16))
        return context.makeImage()!
    }
    static func write(_ image: CGImage, to url: URL, type: UTType) throws {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
    }
}
