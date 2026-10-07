import CoreGraphics
import Foundation

/// Window and browser chrome. M1 draws no title or address text (that arrives in M2): the Window frame has
/// traffic lights only, the Browser frame adds an empty address pill.
enum Frames {
    static func drawBar(_ ctx: CGContext, rect: CGRect, kind: Frame, dark: Bool, space: CGColorSpace) {
        guard kind != .none, rect.height > 0 else { return }
        let b = rect.height
        func color(_ hex: UInt32, _ alpha: Double = 1) -> CGColor { SRGB(hex: hex).cgColor(in: space, alpha: alpha) }

        ctx.setFillColor(color(dark ? 0x2a2c33 : 0xececef))
        ctx.fill(rect)
        let line = max(1, b / 60)
        ctx.setFillColor(dark ? CGColor(colorSpace: space, components: [1, 1, 1, 0.07])! : CGColor(colorSpace: space, components: [0, 0, 0, 0.10])!)
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: line))

        let centreY = rect.midY
        for (i, hex) in [UInt32(0xff5f57), 0xfebc2e, 0x28c840].enumerated() {
            let r = b * 0.11
            ctx.setFillColor(color(hex))
            ctx.fillEllipse(in: CGRect(x: rect.minX + b * 0.42 + Double(i) * b * 0.36 - r, y: centreY - r, width: 2 * r, height: 2 * r))
        }
        if kind == .browser {
            let pillWidth = min(rect.width * 0.5, b * 9), pillHeight = b * 0.5
            let pill = CGRect(x: rect.midX - pillWidth / 2, y: centreY - pillHeight / 2, width: pillWidth, height: pillHeight)
            ctx.setFillColor(color(dark ? 0x1a1c21 : 0xffffff))
            ctx.addPath(CGPath(roundedRect: pill, cornerWidth: pillHeight / 2, cornerHeight: pillHeight / 2, transform: nil))
            ctx.fillPath()
        }
    }
}
