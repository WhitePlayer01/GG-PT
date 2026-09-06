import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/* 图片动画在后台验证并转换为 PNG 帧；视频验证后保留原文件与首帧。
 对文件数、文件体积和解码总像素设上限，防止超大素材耗尽内存。 */
enum ArtworkImporter {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("二爷收着/appearance-assets", isDirectory: true)
    }

    static func importArtwork(from url: URL, root: URL = root) async throws -> CustomArtwork {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if ["mov", "mp4"].contains(url.pathExtension.lowercased()) {
            return try await VideoArtworkImporter.importVideo(from: url, root: root)
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        let isSequence = values.isDirectory == true
        let urls: [URL]
        if isSequence {
            urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                .filter { $0.pathExtension.lowercased() == "png" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } else { urls = [url] }
        guard (1...120).contains(urls.count) else { throw failure("请选择 1–120 张 PNG 的文件夹。") }
        let id = UUID().uuidString
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var succeeded = false
        // 导入失败只清理此次新建目录，不碰原文件或已保存方案。
        defer { if !succeeded { try? FileManager.default.removeItem(at: directory) } }
        var durations: [Double] = []
        var pixelBytes = 0
        var inputBytes = 0
        for sourceURL in urls {
            let info = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            inputBytes += info.fileSize ?? 0
            guard info.isRegularFile == true, inputBytes <= 64 * 1024 * 1024,
                  ["png", "jpg", "jpeg", "gif"].contains(sourceURL.pathExtension.lowercased()),
                  let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
                throw failure("请选择 PNG、JPEG、GIF、MOV、MP4 或 PNG 序列文件夹，总大小不超过 64 MB。")
            }
            let count = CGImageSourceGetCount(source)
            guard count > 0, durations.count + count <= 120 else { throw failure("动画最多支持 120 帧。") }
            for frame in 0..<count {
                try autoreleasepool {
                    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, frame, nil) as? [CFString: Any],
                          let width = properties[kCGImagePropertyPixelWidth] as? Int,
                          let height = properties[kCGImagePropertyPixelHeight] as? Int,
                          width > 0, height > 0, width <= 4096, height <= 4096 else {
                        throw failure("图片无法读取，或尺寸超过 4096 × 4096。")
                    }
                    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 768, kCGImageSourceCreateThumbnailWithTransform: true]
                    guard let image = CGImageSourceCreateThumbnailAtIndex(source, frame, options as CFDictionary) else {
                        throw failure("第 \(frame + 1) 帧无法解码，请换一个文件。")
                    }
                    pixelBytes += image.width * image.height * 4
                    guard pixelBytes <= 96 * 1024 * 1024 else { throw failure("动画解码后超过 96 MB，请减少帧数或尺寸。") }
                    let output = directory.appendingPathComponent("\(durations.count).png")
                    guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                        throw failure("无法写入本机素材目录。")
                    }
                    CGImageDestinationAddImage(destination, image, nil)
                    guard CGImageDestinationFinalize(destination) else { throw failure("素材保存失败，请检查剩余空间。") }
                    let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                    let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                        ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? (1.0 / 12.0)
                    durations.append(min(10, max(0.02, delay.isFinite ? delay : 0.1)))
                }
            }
        }
        succeeded = true
        return CustomArtwork(directory: id, name: url.lastPathComponent, durations: durations,
                             preservesMotion: durations.count == 1)
    }

    static func loadFrames(_ asset: CustomArtwork, root: URL = root) throws -> [CGImage] {
        guard UUID(uuidString: asset.directory) != nil, (1...120).contains(asset.durations.count) else {
            throw failure("素材记录损坏，请重新导入。")
        }
        var decodedBytes = 0
        return try asset.durations.indices.map {
            let image = try loadFrame(asset, index: $0, root: root)
            decodedBytes += image.bytesPerRow * image.height
            guard decodedBytes <= 96 * 1024 * 1024 else { throw failure("素材超出播放内存限制，请重新导入。") }
            return image
        }
    }

    /* 常驻播放每次只解码需要的一帧；尺寸验证在解码前完成。 */
    static func loadFrame(_ asset: CustomArtwork, index: Int, root: URL = root) throws -> CGImage {
        guard UUID(uuidString: asset.directory) != nil, (1...120).contains(asset.durations.count),
              asset.durations.indices.contains(index) else { throw failure("素材记录损坏，请重新导入。") }
        let url = root.appendingPathComponent(asset.directory).appendingPathComponent("\(index).png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 768, height <= 768,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw failure("素材副本缺失或损坏，请重新导入。")
        }
        return image
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "CustomArtwork", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/* 预览和桌面使用同一播放组件。图片素材按需加载并限制缓存，视频交给原生播放器。
 错误时继续显示内置形象，并在设置预览内说明原因。 */
struct CustomArtworkView<Fallback: View>: View {
    let asset: CustomArtwork
    var loops = true
    var playing = true
    var quiet = false
    var showsErrors = false
    @ViewBuilder var fallback: () -> Fallback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame: CGImage?
    @State private var loader = ArtworkFrameLoader()
    @State private var error = ""
    @State private var startedAt = Date()
    @State private var elapsed = 0.0
    @State private var finished = false

    private var paused: Bool { reduceMotion || !playing || !asset.isAnimated || finished || !error.isEmpty }
    var body: some View {
        // 素材只有每秒几帧时，避免仍按每秒三十次计算相同画面。
        TimelineView(.animation(minimumInterval: max(quiet ? 1.0 / 12 : 1.0 / 30, asset.durations.min() ?? 1.0 / 30), paused: paused || asset.video != nil)) { context in
            let time = elapsed + (paused ? 0 : max(0, context.date.timeIntervalSince(startedAt)))
            Group {
                if let video = asset.video, !reduceMotion {
                    if error.isEmpty {
                        VideoArtworkPlayer(url: ArtworkImporter.root.appendingPathComponent(asset.directory)
                            .appendingPathComponent("video.\(video.fileExtension)"), playing: playing, loops: loops) { error = $0 }
                            .scaleEffect(asset.scale).offset(x: asset.offsetX, y: asset.offsetY)
                    } else { fallback() }
                } else if frame == nil || !error.isEmpty { fallback() }
                else {
                    Image(decorative: frame!, scale: 1)
                        .resizable().scaledToFit()
                        .scaleEffect(asset.scale)
                        .offset(x: asset.offsetX, y: asset.offsetY)
                }
            }
            .task(id: "\(asset.directory)-\(reduceMotion)-\(asset.frameIndex(at: reduceMotion ? 0 : time, loops: loops))") {
                guard asset.video == nil || reduceMotion else { return }
                do {
                    let image = try await loader.image(asset, index: asset.frameIndex(at: reduceMotion ? 0 : time, loops: loops))
                    // 快速切帧或切换素材后，过期解码结果不能覆盖新画面。
                    guard !Task.isCancelled else { return }
                    frame = image
                    if !loops && asset.frameIndex(at: time, loops: false) == asset.durations.count - 1 {
                        // 末帧已显示，后续保持原图即可，无需继续刷新。
                        finished = true
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = error.localizedDescription
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showsErrors && !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red).padding(8).background(.regularMaterial)
            }
        }
        .onChange(of: paused) { value in
            if value { elapsed += max(0, Date().timeIntervalSince(startedAt)) }
            else { startedAt = Date() }
        }
        .task(id: asset.directory) {
            frame = nil; error = ""; elapsed = 0; finished = false; startedAt = Date()
        }
        .onDisappear {
            frame = nil
            // 丢弃该视图的缓存，关闭设置预览后不继续保留动画图片。
            loader = ArtworkFrameLoader()
        }
    }
}


/* 串行后台解码，最多保留六帧（768px 方图约 13.5 MB）。
 帧数再多也不整段展开；多个请求共用此队列，避免并发解码抬高峰值内存。 */
actor ArtworkFrameLoader {
    private let root: URL
    init(root: URL = ArtworkImporter.root) { self.root = root }
    private var directory = ""
    private var frames: [Int: CGImage] = [:]
    private var order: [Int] = []

    func image(_ asset: CustomArtwork, index: Int) throws -> CGImage {
        try Task.checkCancellation()
        if directory != asset.directory {
            frames.removeAll(); order.removeAll(); directory = asset.directory
        }
        if let image = frames[index] { return image }
        let image = try autoreleasepool { try ArtworkImporter.loadFrame(asset, index: index, root: root) }
        try Task.checkCancellation()
        if order.count == 6 { frames.removeValue(forKey: order.removeFirst()) }
        frames[index] = image; order.append(index)
        return image
    }
}
