import CoreGraphics
import PremiumShotCore

/// Presentation only: interpolates complete renders, never recipes or endpoint hues.
enum GradientCrossfade {
    static func image(from: CGImage, to: CGImage, fraction: Double) -> CGImage? {
        guard
            let context = CGContext(
                data: nil, width: to.width, height: to.height,
                bitsPerComponent: 8, bytesPerRow: to.width * 4,
                space: to.colorSpace ?? ExportProfile.srgb.colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: to.width, height: to.height)
        context.draw(from, in: rect)
        context.setAlpha(fraction)
        context.draw(to, in: rect)
        return context.makeImage()
    }
}
