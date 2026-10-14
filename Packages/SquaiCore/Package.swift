// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SquaiCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SquaiCore", targets: ["SquaiCore"]),
    ],
    targets: [
        .target(name: "SquaiCore"),
        .testTarget(name: "SquaiCoreTests", dependencies: ["SquaiCore"]),
    ],
    swiftLanguageModes: [.v5]
)
