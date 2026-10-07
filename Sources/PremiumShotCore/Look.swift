import Foundation

/// An sRGB colour given as 0...255 channels. Look colours are always sRGB; they are converted into the
/// render colour space before blending (see `ExportProfile`).
public struct SRGB: Equatable, Sendable {
    public let r: Double, g: Double, b: Double   // 0...1
    public init(hex: UInt32) {
        r = Double((hex >> 16) & 0xff) / 255
        g = Double((hex >> 8) & 0xff) / 255
        b = Double(hex & 0xff) / 255
    }
    public init(_ r: Int, _ g: Int, _ b: Int) {
        self.r = Double(r) / 255; self.g = Double(g) / 255; self.b = Double(b) / 255
    }
}

/// A radial gradient from `color` at the centre to the same colour at zero alpha at `radius`.
public struct Blob: Equatable, Sendable {
    public let x: Double, y: Double          // centre, fraction of width and height
    public let radius: Double                // fraction of the longest edge
    public let color: SRGB
    init(_ x: Double, _ y: Double, _ radius: Double, _ hex: UInt32) {
        self.x = x; self.y = y; self.radius = radius; color = SRGB(hex: hex)
    }
}

public struct Look: Sendable {
    public let id: LookID
    public let name: String
    /// True when the look is dark, which selects a light hairline around the window.
    public let isDark: Bool
    public let isTransparent: Bool
    public let base: SRGB?
    public let blobs: [Blob]
    public let shadowMultiplier: Double
    public let shadowTint: SRGB

    /// The five built-in looks. Numbers come from the approved mock (spec section 7).
    public static let all: [Look] = [
        Look(id: .dawn, name: "Dawn", isDark: false, isTransparent: false, base: SRGB(hex: 0xf2d6cb),
             blobs: [Blob(0.10, 0.05, 0.85, 0xffb59e), Blob(0.95, 0.10, 0.70, 0xdcc4ff),
                     Blob(0.85, 1.00, 0.90, 0xffd8a6), Blob(0.00, 0.95, 0.70, 0xf7b6cc)],
             shadowMultiplier: 0.80, shadowTint: SRGB(96, 44, 44)),
        Look(id: .tide, name: "Tide", isDark: true, isTransparent: false, base: SRGB(hex: 0x0b2a48),
             blobs: [Blob(0.10, 0.05, 0.90, 0x1f72e6), Blob(0.95, 0.95, 0.95, 0x14b8a6),
                     Blob(0.55, 0.55, 0.70, 0x0a1f3a), Blob(0.95, 0.05, 0.50, 0x7b93ff)],
             shadowMultiplier: 1.15, shadowTint: SRGB(0, 10, 34)),
        Look(id: .paper, name: "Paper", isDark: false, isTransparent: false, base: SRGB(hex: 0xecebe6),
             blobs: [Blob(0.20, 0.05, 0.90, 0xffffff), Blob(0.95, 1.00, 0.90, 0xdad7cc)],
             shadowMultiplier: 0.65, shadowTint: SRGB(44, 40, 30)),
        Look(id: .graphite, name: "Graphite", isDark: true, isTransparent: false, base: SRGB(hex: 0x121419),
             blobs: [Blob(0.15, 0.00, 0.90, 0x2b3342), Blob(0.95, 0.95, 0.90, 0x1b2230),
                     Blob(0.90, 0.10, 0.50, 0x3a3150)],
             shadowMultiplier: 1.40, shadowTint: SRGB(0, 0, 0)),
        Look(id: .clear, name: "Clear", isDark: false, isTransparent: true, base: nil, blobs: [],
             shadowMultiplier: 1.00, shadowTint: SRGB(20, 26, 48)),
    ]

    public static func look(_ id: LookID) -> Look { all.first { $0.id == id }! }
}
