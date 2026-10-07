import Foundation

public struct PixelRect: Equatable, Sendable {
    public var x: Int, y: Int, width: Int, height: Int
    public init(x: Int, y: Int, width: Int, height: Int) { self.x = x; self.y = y; self.width = width; self.height = height }
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
    /// Height of the frame bar in output pixels (0 for no frame).
    public let bar: Int
    public let cornerRadius: Double
    public let keyShadow: Shadow
    public let ambientShadow: Shadow

    public struct Shadow: Equatable, Sendable {
        public let blur: Double, offsetY: Double, alpha: Double
    }

    /// The screenshot area inside the window, y from the top.
    public var content: PixelRect {
        PixelRect(x: window.x, y: window.y + bar, width: window.width, height: window.height - bar)
    }

    /// True when the screenshot is placed 1:1 on the pixel grid, so it can be drawn without interpolation.
    public var isPixelExact: Bool { screenshotScale == 1 }
}

public enum LayoutEngine {
    public static let maxLongEdge = 4096.0

    /// Port of the mock's `computeLayout` as a pure function (spec section 7).
    public static func resolve(sourceWidth: Int, sourceHeight: Int, recipe: Recipe) -> Layout {
        let barSource = Double(recipe.frame.barHeight)
        let ww = Double(sourceWidth), wh = Double(sourceHeight) + barSource
        let k = lerp(0.03, 0.19, Double(recipe.space) / 100)

        var canvasW: Double, canvasH: Double, s: Double
        if let fixed = recipe.shape.canvas {
            canvasW = fixed.width; canvasH = fixed.height
            let m = k * min(canvasW, canvasH)
            s = min((canvasW - 2 * m) / ww, (canvasH - 2 * m) / wh, 1)
        } else {
            let m = min(420, max(36, k * min(ww, wh)))
            s = 1; canvasW = ww + 2 * m; canvasH = wh + 2 * m
        }

        // The cap is applied once, to the canvas and the scale together, then sizes are rounded to integers.
        let f = min(1, maxLongEdge / max(canvasW, canvasH))
        s *= f
        let outW = max(1, Int((canvasW * f).rounded())), outH = max(1, Int((canvasH * f).rounded()))

        // Window rectangle, centred and lifted by 0.8% of the height, snapped to whole pixels.
        let w = max(1, Int((ww * s).rounded())), h = max(1, Int((wh * s).rounded()))
        let x = Int((Double(outW - w) / 2).rounded())
        let y = Int((Double(outH - h) / 2 - Double(outH) * 0.008).rounded())
        let bar = Int((barSource * s).rounded())

        let look = Look.look(recipe.look)
        let t = Double(recipe.shadow) / 100 * look.shadowMultiplier
        let l = (Double(w) * Double(h)).squareRoot()
        return Layout(
            width: outW, height: outH, capped: f < 1, screenshotScale: s,
            window: PixelRect(x: x, y: y, width: w, height: h), bar: bar,
            cornerRadius: lerp(0, 64, Double(recipe.radius) / 100) * s,
            keyShadow: .init(blur: l * 0.05 * t, offsetY: l * 0.032 * t, alpha: min(0.6, 0.10 + 0.26 * t)),
            ambientShadow: .init(blur: l * 0.18 * t, offsetY: l * 0.05 * t, alpha: min(0.4, 0.05 + 0.14 * t)))
    }
}

@inline(__always) func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
