// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PremiumShot",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "PremiumShotApp", targets: ["PremiumShotApp"]),
    ],
    targets: [
        // Rendering, layout, recipes, image input and PNG output.
        .target(name: "PremiumShotCore"),
        // Native panel, controls, input and output integration.
        .target(name: "PremiumShotMac", dependencies: ["PremiumShotCore"]),
        .executableTarget(name: "PremiumShotApp", dependencies: ["PremiumShotCore", "PremiumShotMac"]),
        .testTarget(name: "PremiumShotCoreTests", dependencies: ["PremiumShotCore"]),
        .testTarget(name: "PremiumShotMacTests", dependencies: ["PremiumShotMac", "PremiumShotCore"]),
    ]
)
