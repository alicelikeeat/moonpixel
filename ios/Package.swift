// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MoonPixelCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MoonPixelCore", targets: ["MoonPixelCore"])],
    targets: [
        .target(name: "MoonPixelCore", path: "Sources/MoonPixelCore"),
        .testTarget(name: "MoonPixelCoreTests", dependencies: ["MoonPixelCore"], path: "Tests/MoonPixelCoreTests"),
    ]
)
