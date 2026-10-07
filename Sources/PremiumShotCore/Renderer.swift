import CoreGraphics
import Foundation

/// The result of a render: the pixels and the resolved output specification they were drawn from.
public struct RenderResult: @unchecked Sendable {   // CGImage is immutable
    public let image: CGImage
    public let layout: Layout
    public let profile: ExportProfile
}

/// The only place pixels are composed. Preview, Copy, Save, drag-out and the CLI all come through here.
public enum Renderer {
    /// Draws the full-size output for `recipe`. Throws if the bitmap cannot be allocated.
    public static func render(source: SourceImage, recipe: Recipe, profile: ExportProfile = .srgb) throws -> RenderResult {
        try recipe.validate()
        let layout = LayoutEngine.resolve(sourceWidth: source.width, sourceHeight: source.height, recipe: recipe)
        let space = profile.colorSpace
        let W = layout.width, H = layout.height

        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw PremiumShotError.renderFailed("The \(W) × \(H) bitmap could not be allocated.")
        }
        ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true)
        let look = Look.look(recipe.look)

        drawBackground(ctx, look: look, width: W, height: H, space: space)

        // Window geometry, converted from top-left pixels to CoreGraphics' bottom-left origin.
        let win = layout.window
        let windowRect = CGRect(x: win.x, y: H - win.y - win.height, width: win.width, height: win.height)
        let radius = min(layout.cornerRadius, Double(min(win.width, win.height)) / 2)
        let windowPath = CGPath(roundedRect: windowRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        drawShadow(ctx, rect: windowRect, radius: radius, shadow: layout.ambientShadow, look: look, space: space, canvasWidth: W)
        drawShadow(ctx, rect: windowRect, radius: radius, shadow: layout.keyShadow, look: look, space: space, canvasWidth: W)

        // Screenshot and frame bar, clipped to the rounded window.
        ctx.saveGState()
        ctx.addPath(windowPath); ctx.clip()
        let content = layout.content
        let contentRect = CGRect(x: content.x, y: H - content.y - content.height, width: content.width, height: content.height)
        // At 1:1 the screenshot sits on the pixel grid and is copied without resampling so text stays crisp.
        ctx.interpolationQuality = layout.isPixelExact ? .none : .high
        ctx.draw(source.cgImage, in: contentRect)
        if layout.bar > 0 {
            let barRect = CGRect(x: win.x, y: H - win.y - layout.bar, width: win.width, height: layout.bar)
            Frames.drawBar(ctx, rect: barRect, kind: recipe.frame, dark: source.topLuminance < 0.42, space: space)
        }
        ctx.restoreGState()

        // 1 px hairline around the window.
        let hairline = max(1.0, Double(H) / 800)
        ctx.setLineWidth(hairline)
        ctx.setStrokeColor(look.isDark ? CGColor(colorSpace: space, components: [1, 1, 1, 0.16])! : CGColor(colorSpace: space, components: [0, 0, 0, 0.11])!)
        let inset = hairline / 2
        ctx.addPath(CGPath(roundedRect: windowRect.insetBy(dx: inset, dy: inset), cornerWidth: max(0, radius - inset), cornerHeight: max(0, radius - inset), transform: nil))
        ctx.strokePath()

        guard let image = ctx.makeImage() else { throw PremiumShotError.renderFailed("The bitmap could not be read back.") }
        return RenderResult(image: image, layout: layout, profile: profile)
    }

    /// The settled preview: the export render, area-averaged down to `height`. Because it is derived from
    /// the export, preview and file cannot disagree about composition or grain.
    public static func renderPreview(source: SourceImage, recipe: Recipe, profile: ExportProfile = .srgb, height: Int) throws -> RenderResult {
        let full = try render(source: source, recipe: recipe, profile: profile)
        guard height < full.layout.height, let small = Downsample.image(full.image, toHeight: height) else { return full }
        return RenderResult(image: small, layout: full.layout, profile: profile)
    }

    // MARK: Drawing

    private static func drawBackground(_ ctx: CGContext, look: Look, width W: Int, height H: Int, space: CGColorSpace) {
        guard !look.isTransparent, let base = look.base else { return }
        ctx.setFillColor(base.cgColor(in: space))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let longest = Double(max(W, H))
        for blob in look.blobs {
            let centre = CGPoint(x: blob.x * Double(W), y: Double(H) - blob.y * Double(H))   // y measured from the top in the recipe
            guard let gradient = CGGradient(colorsSpace: space,
                                            colors: [blob.color.cgColor(in: space, alpha: 1), blob.color.cgColor(in: space, alpha: 0)] as CFArray,
                                            locations: [0, 1]) else { continue }
            ctx.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre,
                                   endRadius: blob.radius * longest, options: [])
        }
        if let grain = Grain.image(width: W, height: H, space: space) {
            ctx.saveGState()
            ctx.setBlendMode(.overlay); ctx.setAlpha(Grain.opacity)
            ctx.interpolationQuality = .none
            ctx.draw(grain, in: CGRect(x: 0, y: 0, width: W, height: H))
            ctx.restoreGState()
        }
    }

    /// Draws only the shadow of a rounded rectangle. The casting shape is drawn far outside the canvas and
    /// its shadow is offset back, so no dark fill sits under the screenshot's anti-aliased corners.
    private static func drawShadow(_ ctx: CGContext, rect: CGRect, radius: Double, shadow: Layout.Shadow, look: Look, space: CGColorSpace, canvasWidth: Int) {
        guard shadow.alpha > 0, shadow.blur >= 0 else { return }
        let away = Double(canvasWidth) * 4 + rect.width
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: away, height: -shadow.offsetY), blur: CGFloat(shadow.blur),
                      color: look.shadowTint.cgColor(in: space, alpha: shadow.alpha))
        ctx.setFillColor(CGColor(colorSpace: space, components: [0, 0, 0, 1])!)
        ctx.addPath(CGPath(roundedRect: rect.offsetBy(dx: -away, dy: 0), cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
    }
}

enum Downsample {
    /// Halves repeatedly while the image is more than twice the target, then resizes to the exact size.
    static func image(_ image: CGImage, toHeight targetHeight: Int) -> CGImage? {
        let scale = Double(targetHeight) / Double(image.height)
        let targetWidth = max(1, Int((Double(image.width) * scale).rounded()))
        var current = image
        while current.height > targetHeight * 2 {
            guard let half = resize(current, width: max(1, current.width / 2), height: max(1, current.height / 2)) else { return nil }
            current = half
        }
        return resize(current, width: targetWidth, height: max(1, targetHeight))
    }

    private static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let space = image.colorSpace,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
