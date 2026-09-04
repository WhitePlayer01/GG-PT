import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@main
struct ListeningPreviewRenderer {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        guard CommandLine.arguments.count >= 2 else { fatalError("请提供 GIF 输出路径或 --all 输出目录") }
        if CommandLine.arguments[1] == "--all" {
            guard CommandLine.arguments.count == 3 else { fatalError("请提供输出目录") }
            let directory = URL(fileURLWithPath: CommandLine.arguments[2])
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for variant in ListeningAnimationVariant.allCases {
                render(url: directory.appendingPathComponent("\(variant.title).gif"), variants: [variant])
            }
            var playlist = ListeningAnimationPlaylist()
            let sequence = (0..<5).map { _ in playlist.next() }
            render(url: directory.appendingPathComponent("五款随机轮播.gif"), variants: sequence)
            render(url: directory.appendingPathComponent("五款动效总览.gif"), variants: ListeningAnimationVariant.allCases, gallery: true)
        } else {
            render(url: URL(fileURLWithPath: CommandLine.arguments[1]), variants: [.sway])
        }
    }

    @MainActor static func render(url: URL, variants: [ListeningAnimationVariant], gallery: Bool = false) {
        let framesPerVariant = 144
        let frameCount = gallery ? framesPerVariant : framesPerVariant * variants.count
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            fatalError("无法创建 GIF")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<frameCount {
            autoreleasepool {
                let index = frame % framesPerVariant
                let time = Double(index) / 15
                let content: AnyView
                if gallery {
                    content = AnyView(HStack(spacing: 0) {
                        ForEach(variants) { variant in
                            VStack(spacing: 8) {
                                ListeningPetFrame(time: time, variant: variant)
                                Text(variant.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white)
                            }.padding(.vertical, 14)
                        }
                    }.background(Color(red: 0.08, green: 0.12, blue: 0.15)))
                } else {
                    let variant = variants[frame / framesPerVariant]
                    content = AnyView(ListeningPetFrame(time: time, variant: variant))
                }
                let renderer = ImageRenderer(content: content)
                renderer.scale = gallery ? 1 : 1.5
                renderer.isOpaque = gallery
                guard let image = renderer.cgImage else { fatalError("无法渲染听歌动画") }
                CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frame % 3 == 1 ? 0.06 : 0.07]] as CFDictionary)
            }
        }
        precondition(CGImageDestinationFinalize(destination))
        print(url.path)
    }
}
