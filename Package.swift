// swift-tools-version: 6.0
import PackageDescription

// Swift Package Manager 清单：定义 macOS 13 及以上可运行的单一桌面应用目标。
let package = Package(
    name: "PetSorter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PetSorter", targets: ["PetSorter"])
    ],
    targets: [
        // 资源由构建脚本复制到标准 App Bundle，因此不交给 SwiftPM 自动处理。
        .executableTarget(
            name: "PetSorter",
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
