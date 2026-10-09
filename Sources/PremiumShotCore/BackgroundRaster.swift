import CoreGraphics
import Foundation
import Synchronization

/// One full background and one interactive background. Mutex protects immutable CGImages across render workers.
/// Geometry edits reuse the expensive background composition.
enum BackgroundRaster {
    struct Key: Equatable {
        let look: LookID
        let width: Int
        let height: Int
        let profile: ExportProfile
        let grainScale: Double
        let gradient: CustomGradient.Identity?
    }
    struct Entry {
        let key: Key
        let image: CGImage
    }
    private static let cache = Mutex<[Entry]>([])

    static func image(
        look: Look, recipe: Recipe, width: Int, height: Int, profile: ExportProfile, grainScale: Double
    ) throws
        -> CGImage?
    {
        guard !look.isTransparent, let base = look.base else { return nil }
        let gradient =
            look.id == .custom
            ? CustomGradient.Identity(
                from: GradientHues.normalized(recipe.gradientFrom),
                to: GradientHues.normalized(recipe.gradientTo)) : nil
        let key = Key(
            look: look.id, width: width, height: height, profile: profile, grainScale: grainScale,
            gradient: gradient)
        if let found = cache.withLock({ $0.first { $0.key == key }?.image }) { return found }
        if look.id == .custom {
            let image = try CustomGradient.image(
                width: width, height: height, from: recipe.gradientFrom, to: recipe.gradientTo,
                grainOpacity: grainScale < 1 ? Double(Grain.opacity) * grainScale : 0)
            cache.withLock { entries in
                entries.removeAll { ($0.key.grainScale == 1) == (grainScale == 1) }
                entries.append(Entry(key: key, image: image))
            }
            return image
        }
        let space = profile.colorSpace
        // Gradients vary slowly. Sample the colour field at a bounded resolution, then apply export grain
        // at native pixel coordinates. Screenshot pixels never pass through this field.
        let fieldScale = min(1, Double(grainScale == 1 ? 1024 : 384) / Double(max(width, height)))
        let fw = max(1, Int((Double(width) * fieldScale).rounded()))
        let fh = max(1, Int((Double(height) * fieldScale).rounded()))
        func context(_ w: Int, _ h: Int) -> CGContext? {
            CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )
        }
        guard let field = context(fw, fh) else {
            throw PremiumShotError.renderFailed("The background could not be allocated.")
        }
        field.setFillColor(base.cgColor(in: space))
        field.fill(CGRect(x: 0, y: 0, width: fw, height: fh))
        for blob in look.blobs {
            try Task.checkCancellation()
            let centre = CGPoint(x: blob.x * Double(fw), y: Double(fh) * (1 - blob.y))
            let gradient = CGGradient(
                colorsSpace: space,
                colors: [blob.color.cgColor(in: space), blob.color.cgColor(in: space, alpha: 0)] as CFArray,
                locations: [0, 1])!
            field.drawRadialGradient(
                gradient, startCenter: centre, startRadius: 0, endCenter: centre,
                endRadius: blob.radius * Double(max(fw, fh)), options: [])
        }
        try Task.checkCancellation()
        // Cache the smooth field, not another full export-sized bitmap. The full-size grain
        // is fused into the final composition context before any screenshot pixels are drawn.
        if grainScale < 1 {
            try Grain.apply(to: field, opacity: Double(Grain.opacity) * grainScale)
        }
        guard let image = field.makeImage() else {
            throw PremiumShotError.renderFailed("The background could not be read.")
        }
        try Task.checkCancellation()
        cache.withLock { entries in
            entries.removeAll { ($0.key.grainScale == 1) == (grainScale == 1) }
            entries.append(Entry(key: key, image: image))
        }
        return image
    }
}
