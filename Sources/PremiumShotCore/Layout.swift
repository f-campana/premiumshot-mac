import Foundation

public struct PixelRect: Codable, Equatable, Sendable {
    public var x: Int, y: Int, width: Int, height: Int
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// The **one resolved output specification**. The caption, the preview, the saved file and the clipboard
/// image all use these numbers; nothing downstream applies its own cap or rounding.
public struct Layout: Equatable, Sendable {
    /// Output size in pixels, after the cap.
    public let width: Int, height: Int
    /// True exactly when the long-edge cap reduced the size.
    public let capped: Bool
    /// How large the screenshot itself is drawn compared with its own pixels. Never above 1.
    public let screenshotScale: Double
    /// The window (frame bar plus screenshot), snapped to whole output pixels, y measured from the top.
    public let window: PixelRect
    public let cornerRadius: Double
    public let keyShadow: Shadow
    public let ambientShadow: Shadow

    public struct Shadow: Equatable, Sendable {
        public let blur: Double, offsetY: Double, alpha: Double
    }

    /// The screenshot area inside the window, y from the top.
    public var content: PixelRect { window }

    /// True when the screenshot is placed 1:1 on the pixel grid, so it can be drawn without interpolation.
    public var isPixelExact: Bool { screenshotScale == 1 }
}

public enum LayoutEngine {
    public static let maxLongEdge = 4096.0
    /// Core Graphics shadow falloff, verified by the transparent-border regressions.
    public static let shadowReachFactor = 1.1

    struct ContinuousGeometry {
        let width: Double, height: Double, scale: Double, margin: Double
    }
    static func continuous(sourceWidth: Int, sourceHeight: Int, recipe: Recipe) -> ContinuousGeometry {
        let ww = Double(sourceWidth)
        let wh = Double(sourceHeight)
        let u = Double(recipe.space) / 100
        let k = lerp(0.03, 0.19, u)
        if let fixed = recipe.shape.canvas {
            let short = min(fixed.width, fixed.height)
            let nativeFits = ww <= fixed.width - 0.06 * short && wh <= fixed.height - 0.06 * short
            let margin = k * short
            let scale =
                nativeFits
                ? lerp(1, 0.7, u)
                : min(1, (fixed.width - 2 * margin) / ww, (fixed.height - 2 * margin) / wh)
            return .init(width: fixed.width, height: fixed.height, scale: scale, margin: margin)
        }
        let margin = max(k * min(ww, wh), lerp(8, 36, u))
        return .init(width: ww + 2 * margin, height: wh + 2 * margin, scale: 1, margin: margin)
    }

    public static func resolve(sourceWidth: Int, sourceHeight: Int, recipe: Recipe) -> Layout {
        let ideal = continuous(sourceWidth: sourceWidth, sourceHeight: sourceHeight, recipe: recipe)
        let ww = Double(sourceWidth)
        let wh = Double(sourceHeight)
        let f = min(1, maxLongEdge / max(ideal.width, ideal.height))
        // A one-pixel source still needs two physical pixels on each side after the cap.
        var outW = max(5, Int((ideal.width * f).rounded()))
        var outH = max(5, Int((ideal.height * f).rounded()))
        // Grow the short Fit edge for physical gutters instead of enlarging the source
        // as a newly rounded canvas pixel becomes available at the next Space value.
        if recipe.shape == .fit {
            outW = min(4096, max(outW, max(1, Int((ww * ideal.scale * f).rounded())) + 4))
            outH = min(4096, max(outH, max(1, Int((wh * ideal.scale * f).rounded())) + 4))
        }
        let s = min(ideal.scale * f, Double(outW - 4) / ww, Double(outH - 4) / wh)
        let w = min(outW - 4, max(1, Int((ww * s).rounded())))
        let sourceH = min(outH - 4, max(1, Int((Double(sourceHeight) * s).rounded())))
        let h = sourceH
        let free = outH - h
        let lift = min(Int((0.008 * Double(outH)).rounded()), free / 4, max(0, free / 2 - 2))
        let x = (outW - w) / 2
        let y = max(2, min(outH - h - 2, Int((Double(free) / 2).rounded()) - lift))
        let l = sqrt(Double(w) * Double(h))
        let t = Double(recipe.shadow) / 100 * Look.look(recipe.look).shadowMultiplier
        let ramp = min(1, t / 0.1)
        func fitted(blur: Double, offset: Double, alpha: Double) -> Layout.Shadow {
            guard t > 0 else { return .init(blur: 0, offsetY: 0, alpha: 0) }
            let extent = shadowReachFactor * blur
            let limits = [
                (Double(x), extent), (Double(outW - x - w), extent),
                (Double(y), max(0, extent - offset)),
                (Double(outH - y - h), extent + offset),
            ]
            // Reserve a pixel for Quartz kernel and subpixel-offset rounding, without changing geometry.
            let factor = limits.filter { $0.1 > 0 }.reduce(1.0) { min($0, max(0, $1.0 - 1) / $1.1) }
            guard factor * extent >= 0.5 else { return .init(blur: 0, offsetY: 0, alpha: 0) }
            return .init(blur: factor * blur, offsetY: factor * offset, alpha: alpha)
        }
        return Layout(
            width: outW, height: outH, capped: f < 1, screenshotScale: s,
            window: PixelRect(x: x, y: y, width: w, height: h),
            cornerRadius: lerp(0, 64, Double(recipe.radius) / 100) * s,
            keyShadow: fitted(
                blur: l * 0.05 * t, offset: l * 0.032 * t,
                alpha: ramp * min(0.6, 0.10 + 0.26 * t)),
            ambientShadow: fitted(
                blur: l * 0.18 * t, offset: l * 0.05 * t,
                alpha: ramp * min(0.4, 0.05 + 0.14 * t)))
    }
}

@inline(__always) func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
