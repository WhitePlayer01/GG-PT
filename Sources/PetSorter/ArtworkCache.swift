import AppKit
import ImageIO

/// 按显示尺寸解码，不将原始大图完整解压到常驻内存。
/// 800px 覆盖 275pt × 最大 1.45 倍缩放 × Retina 2 倍。
enum ArtworkCache {
    static let maximumPixelSize = 800
    private static let images: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 12
        cache.totalCostLimit = 20 * 1024 * 1024
        return cache
    }()

    static func image(at url: URL) -> NSImage? {
        if let image = images.object(forKey: url as NSURL) { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary) else { return nil }
        let result = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        images.setObject(result, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
        return result
    }
}
