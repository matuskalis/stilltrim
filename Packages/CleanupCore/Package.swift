// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleanupCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CleanupCore", targets: ["CleanupCore"]),
    ],
    targets: [
        .target(name: "CleanupCore"),
        .testTarget(name: "CleanupCoreTests", dependencies: ["CleanupCore"]),
    ]
)
