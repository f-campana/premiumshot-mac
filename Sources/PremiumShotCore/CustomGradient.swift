import CoreGraphics
import Foundation

/// OKLab conversions use the published linear-sRGB matrices. Chroma reduction
/// follows the CSS Color 4 principle, without claiming its full gamut-mapping algorithm.
public struct OKLab: Equatable, Sendable {
    public let l: Double, a: Double, b: Double
    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }
    public init(
        hue: Int, lightness: Double = CustomGradient.lightness, chroma: Double = CustomGradient.chroma
    ) {
        let angle = Double(GradientHues.normalized(hue)) * .pi / 180
        self.init(l: lightness, a: chroma * cos(angle), b: chroma * sin(angle))
    }
    public var chroma: Double { hypot(a, b) }
    public var hue: Double { (atan2(b, a) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360) }
    public func blended(to end: Self, at t: Double) -> Self {
        Self(l: lerp(l, end.l, t), a: lerp(a, end.a, t), b: lerp(b, end.b, t))
    }
    public var linearRGB: LinearRGB {
        let l = pow(self.l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(self.l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(self.l - 0.0894841775 * a - 1.2914855480 * b, 3)
        return LinearRGB(
            r: 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            g: -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            b: -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }
    public var gamutMapped: LinearRGB {
        let original = linearRGB
        if original.inGamut { return original }
        var lo = 0.0
        var hi = 1.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if OKLab(l: l, a: a * mid, b: b * mid).linearRGB.inGamut { lo = mid } else { hi = mid }
        }
        return OKLab(l: l, a: a * lo, b: b * lo).linearRGB
    }
}

public struct LinearRGB: Equatable, Sendable {
    public let r: Double, g: Double, b: Double
    public var inGamut: Bool { (0...1).contains(r) && (0...1).contains(g) && (0...1).contains(b) }
    public var lab: OKLab {
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return OKLab(
            l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }
    public func shaded(by intensity: Double) -> Self {
        Self(r: r * intensity, g: g * intensity, b: b * intensity)
    }
    public var srgb: SRGB {
        func encode(_ v: Double) -> Double { v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055 }
        return SRGB(red: encode(r), green: encode(g), blue: encode(b))
    }
}

public struct GradientHues: Equatable, Sendable {
    public let from: Int, to: Int
    public init(from: Int, to: Int) {
        self.from = from
        self.to = to
    }
    public static func normalized(_ value: Int) -> Int { (value % 360 + 360) % 360 }
    public static func distance(_ a: Int, _ b: Int) -> Int {
        let difference = abs(normalized(a) - normalized(b))
        return min(difference, 360 - difference)
    }
    /// Rejection sampling has a 32-attempt bound. The deterministic fallback
    /// moves start by 180 degrees and keeps a valid 90-degree separation.
    public func randomized<R: RandomNumberGenerator>(using rng: inout R) -> Self {
        for _ in 0..<32 {
            let start = Int.random(in: 0..<360, using: &rng)
            let separation = Int.random(in: 40...140, using: &rng)
            let sign = Bool.random(using: &rng) ? 1 : -1
            let pair = Self(from: start, to: Self.normalized(start + sign * separation))
            if Self.distance(from, pair.from) >= 30 || Self.distance(to, pair.to) >= 30 { return pair }
        }
        let start = Self.normalized(from + 180)
        return Self(from: start, to: Self.normalized(start + 90))
    }
    public static func name(_ hue: Int) -> String {
        switch normalized(hue) {
        case 0..<35, 340..<360: "red"
        case 35..<75: "orange"
        case 75..<115: "yellow"
        case 115..<175: "green"
        case 175..<230: "cyan"
        case 230..<285: "blue"
        default: "purple"
        }
    }
}

/// A single quantised blend-position sampler feeds the controls and all renders.
/// 1/8192 steps bound the positional error to 1/16384; colours are gamut-mapped
/// before 8-bit quantisation. The lookup avoids doing a chroma search per export pixel.
public struct GradientSampler: Sendable {
    public static let steps = 8192
    private let samples: [LinearRGB]
    private let encoded: [SRGB]
    private static let shadingSteps = 4096
    private static let shadingPowers = (0...shadingSteps).map {
        pow(
            CustomGradient.minimumIntensity + (1 - CustomGradient.minimumIntensity) * Double($0)
                / Double(shadingSteps),
            1 / 2.4)
    }
    public init(from: Int, to: Int) {
        let start = OKLab(hue: from)
        let end = OKLab(hue: to)
        samples = (0...Self.steps).map {
            start.blended(to: end, at: Double($0) / Double(Self.steps)).gamutMapped
        }
        encoded = samples.map(\.srgb)
    }
    public func sample(_ t: Double) -> LinearRGB {
        samples[Int((min(1, max(0, t)) * Double(Self.steps)).rounded())]
    }
    /// In the nonlinear transfer branch, encode(v * i) is algebraically
    /// (encode(v) + .055) * i^(1/2.4) - .055. A bounded shading lookup avoids
    /// three pow calls per pixel; its error is checked before byte quantisation.
    public func sampleShaded(_ t: Double, intensity: Double) -> SRGB {
        let index = Int((min(1, max(0, t)) * Double(Self.steps)).rounded())
        let linear = samples[index]
        let base = encoded[index]
        let intensity = min(1, max(CustomGradient.minimumIntensity, intensity))
        let shadeIndex = Int(
            ((intensity - CustomGradient.minimumIntensity) / (1 - CustomGradient.minimumIntensity)
                * Double(Self.shadingSteps)).rounded())
        let factor = Self.shadingPowers[shadeIndex]
        func channel(_ v: Double, _ encoded: Double) -> Double {
            v * intensity <= 0.0031308 ? 12.92 * v * intensity : (encoded + 0.055) * factor - 0.055
        }
        return SRGB(
            red: channel(linear.r, base.r), green: channel(linear.g, base.g), blue: channel(linear.b, base.b))
    }
    public static func endpoint(_ hue: Int) -> SRGB { OKLab(hue: hue).gamutMapped.srgb }
}

public enum CustomGradient {
    public static let lightness = 0.72, chroma = 0.14
    public static let minimumIntensity = 0.97
    public static let shadingLightnessBound = lightness * (1 - cbrt(minimumIntensity))
    struct Identity: Equatable {
        let from: Int, to: Int
        let lightness = CustomGradient.lightness, chroma = CustomGradient.chroma
        let shading = CustomGradient.minimumIntensity, steps = GradientSampler.steps
    }
    public static func field(x: Double, y: Double, width: Int, height: Int) -> (t: Double, intensity: Double)
    {
        let edge = Double(max(width, height))
        let anchors: [(Double, Double, Double, Double)] = [
            (0.10, 0.05, 0.85, 0), (0.95, 0.10, 0.70, 0.30),
            (0.00, 0.95, 0.70, 0.70), (0.85, 1.00, 0.90, 1),
        ]
        var total = 0.12
        var position = 0.06
        var shade = 0.0
        for (ax, ay, radius, value) in anchors {
            // Coordinates are bounded by the export pixel cap, so the overflow-safe
            // hypot path is unnecessary in this per-pixel field.
            let dx = x - ax * Double(width)
            let dy = y - ay * Double(height)
            let distance = sqrt(dx * dx + dy * dy) / (radius * edge)
            let falloff = max(0, 1 - distance)
            let weight = falloff * falloff
            total += weight
            position += weight * value
            shade += weight
        }
        return (position / total, minimumIntensity + (1 - minimumIntensity) * min(1, shade / 1.5))
    }
    public static func image(width: Int, height: Int, from: Int, to: Int, grainOpacity: Double = 0) throws
        -> CGImage
    {
        let sampler = GradientSampler(from: from, to: to)
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: ExportProfile.srgb.colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ),
            let memory = context.data?.assumingMemoryBound(to: UInt8.self)
        else { throw PremiumShotError.renderFailed("The custom background could not be allocated.") }
        for row in 0..<height {
            try Task.checkCancellation()
            for col in 0..<width {
                let f = field(x: Double(col) + 0.5, y: Double(row) + 0.5, width: width, height: height)
                let color = sampler.sampleShaded(f.t, intensity: f.intensity)
                let i = (row * width + col) * 4
                memory[i] = UInt8((color.r * 255).rounded())
                memory[i + 1] = UInt8((color.g * 255).rounded())
                memory[i + 2] = UInt8((color.b * 255).rounded())
                memory[i + 3] = 255
            }
        }
        if grainOpacity > 0 { try Grain.apply(to: context, opacity: grainOpacity) }
        guard let image = context.makeImage() else {
            throw PremiumShotError.renderFailed("The custom background could not be read.")
        }
        return image
    }
}
