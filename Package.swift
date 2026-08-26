// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PetSorter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PetSorter", targets: ["PetSorter"])
    ],
    targets: [
        .executableTarget(
            name: "PetSorter",
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
