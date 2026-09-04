import AppKit
import ImageIO

@main
struct ArtworkCacheTests {
    static func main() {
        let directory = URL(fileURLWithPath: "Sources/PetSorter/Resources")
        let names = ["guan-yu-listening", "guan-yu-listening-nod", "guan-yu-listening-beat",
                     "guan-yu-listening-dance", "guan-yu-listening-zen", "guan-yu-idle"]
        var originalBytes = 0
        var decodedBytes = 0
        for name in names {
            let url = directory.appendingPathComponent(name + ".png")
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
            let width = properties[kCGImagePropertyPixelWidth] as! Int
            let height = properties[kCGImagePropertyPixelHeight] as! Int
            originalBytes += width * height * 4
            let image = ArtworkCache.image(at: url)!
            precondition(image === ArtworkCache.image(at: url), "重复读取应复用缓存")
            let decoded = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            precondition(max(decoded.width, decoded.height) <= ArtworkCache.maximumPixelSize)
            precondition(abs(Double(decoded.width) / Double(decoded.height) - Double(width) / Double(height)) < 0.005)
            precondition(decoded.alphaInfo != .none, "保留透明通道")
            decodedBytes += decoded.bytesPerRow * decoded.height
        }
        precondition(ArtworkCache.image(at: directory.appendingPathComponent("missing.png")) == nil)
        precondition(decodedBytes < originalBytes / 2)
        print("通过：缓存复用、尺寸上限、宽高比、透明通道和缺失图片处理")
        print("六张图解码像素内存：\(originalBytes) → \(decodedBytes) 字节（非进程总内存）")
    }
}
