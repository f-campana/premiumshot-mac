import CoreGraphics
import Foundation

/// The colour space an image is rendered in **and** exported in.
///
/// The spec's default was "render in Display P3, export sRGB". Rendering directly in the export space was
/// chosen for M0 instead: converting twice (source → P3 → sRGB, 8 bits each) cannot keep an sRGB screenshot
/// bit-exact, which acceptance check R5 requires. A wide-gamut working space is a decision for spike S9.
public enum ExportProfile: String, Sendable, CaseIterable {
    case srgb
    case displayP3 = "p3"

    public var colorSpace: CGColorSpace {
        switch self {
        case .srgb: return CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3: return CGColorSpace(name: CGColorSpace.displayP3)!
        }
    }

    /// The colour space name an exported file must decode to.
    public var colorSpaceName: String {
        switch self {
        case .srgb: return CGColorSpace.sRGB as String
        case .displayP3: return CGColorSpace.displayP3 as String
        }
    }
}

extension SRGB {
    /// This colour expressed in `space`, with the given alpha. Look colours are authored in sRGB.
    func cgColor(in space: CGColorSpace, alpha: Double = 1) -> CGColor {
        let source = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, alpha].map { CGFloat($0) })!
        return source.converted(to: space, intent: .defaultIntent, options: nil) ?? source
    }
}
