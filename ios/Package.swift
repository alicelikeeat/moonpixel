// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MoonPixelCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MoonPixelCore", targets: ["MoonPixelCore"]),
        // the core as a C library for the PC front end (Unreal): moonpixel.dll (bridge/include/moonpixel.h)
        .library(name: "MoonPixelBridge", type: .dynamic, targets: ["MoonPixelBridge"]),
    ],
    targets: [
        .target(name: "MoonPixelCore", path: "Sources/MoonPixelCore"),
        .target(name: "MoonPixelBridge", dependencies: ["MoonPixelCore"], path: "Sources/MoonPixelBridge"),
        .testTarget(name: "MoonPixelBridgeTests", dependencies: ["MoonPixelBridge", "MoonPixelCore"], path: "Tests/MoonPixelBridgeTests"),
        .testTarget(name: "MoonPixelCoreTests", dependencies: ["MoonPixelCore"], path: "Tests/MoonPixelCoreTests"),
    ]
)
