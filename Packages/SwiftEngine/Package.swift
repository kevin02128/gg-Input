// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftEngine",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SwiftEngine",
            targets: ["SwiftEngine"]),
    ],
    targets: [
        .target(
            name: "SwiftEngine"),
        .testTarget(
            name: "SwiftEngineTests",
            dependencies: ["SwiftEngine"]),
    ]
)
