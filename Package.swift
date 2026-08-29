// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleanMyMac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CleanMyMacCore", targets: ["CleanMyMacCore"]),
        .executable(name: "CleanMyMac", targets: ["CleanMyMac"]),
    ],
    targets: [
        .target(name: "CleanMyMacCore"),
        .executableTarget(
            name: "CleanMyMac",
            dependencies: ["CleanMyMacCore"]
        ),
        .testTarget(
            name: "CleanMyMacCoreTests",
            dependencies: ["CleanMyMacCore", "CleanMyMac"]
        ),
    ]
)
