// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PremiumShot",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PremiumShotCore", targets: ["PremiumShotCore"]),
        .executable(name: "pshot", targets: ["pshot"]),
        .executable(name: "PremiumShotApp", targets: ["PremiumShotApp"]),
    ],
    targets: [
        // Rendering, layout, recipe, image input and PNG output. CoreGraphics and ImageIO only; no UI.
        .target(name: "PremiumShotCore"),
        // AppKit integration: pasteboard, hotkey, panel, dev-only spike harnesses.
        .target(name: "PremiumShotMac", dependencies: ["PremiumShotCore"]),
        .executableTarget(name: "pshot", dependencies: ["PremiumShotCore"]),
        .executableTarget(name: "PremiumShotApp", dependencies: ["PremiumShotCore", "PremiumShotMac"]),
        // Dev tool: writes the synthetic fixtures into fixtures/.
        .executableTarget(name: "fixturegen"),
        .testTarget(name: "PremiumShotCoreTests", dependencies: ["PremiumShotCore"]),
        .testTarget(name: "PremiumShotMacTests", dependencies: ["PremiumShotMac", "PremiumShotCore"]),
    ]
)
