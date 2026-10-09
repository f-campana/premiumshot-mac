import CoreGraphics
import Foundation

/// The result of a render: the pixels and the resolved output specification they were drawn from.
public struct RenderResult: @unchecked Sendable {  // CGImage is immutable
    public let image: CGImage
    public let layout: Layout
    public let profile: ExportProfile
}

/// The only place pixels are composed. Preview, Copy, Save, drag-out and the CLI all come through here.
public enum Renderer {
    public static func background(recipe: Recipe, width: Int, height: Int) throws -> CGImage? {
        try BackgroundRaster.image(look: Look.look(recipe), recipe: recipe, width: width, height: height,
            profile: .srgb, grainScale: 0)
    }
    /// Draws the full-size output for `recipe`. Throws if the bitmap cannot be allocated.
    public static func render(source: SourceImage, recipe: Recipe, profile: ExportProfile = .srgb) throws
        -> RenderResult
    {
        try recipe.validate()
        let layout = LayoutEngine.resolve(
            sourceWidth: source.width, sourceHeight: source.height, recipe: recipe)
        return try compose(
            source: source, recipe: recipe, profile: profile, layout: layout, height: layout.height)
    }

    /// Direct low-resolution composition for a moving control; output geometry stays full-size.
    public static func renderInteractive(
        source: SourceImage, recipe: Recipe, profile: ExportProfile = .srgb, height: Int
    ) throws -> RenderResult {
        try recipe.validate()
        let layout = LayoutEngine.resolve(
            sourceWidth: source.width, sourceHeight: source.height, recipe: recipe)
        let targetHeight = min(layout.height, max(1, height))
        // Heavily downscaled images produce tiny Quartz blur kernels. Supersample those
        // previews only; ordinary wide screenshots keep the inexpensive direct path.
        let composed = try compose(
            source: source, recipe: recipe, profile: profile, layout: layout,
            height: samplingHeight(layout: layout, target: targetHeight))
        return reduced(composed, layout: layout, height: targetHeight)
    }

    /// UI-only composition at an interpolated geometry. The caller must never encode this result as output.
    public static func renderPresentation(
        source: SourceImage, recipe: Recipe, profile: ExportProfile,
        geometry: PresentationGeometry, height: Int
    ) throws -> RenderResult {
        let reference = LayoutEngine.resolve(
            sourceWidth: source.width, sourceHeight: source.height, recipe: recipe)
        let layout = geometry.layout(reference: reference)
        let targetHeight = min(layout.height, max(1, height))
        let composed = try compose(
            source: source, recipe: recipe, profile: profile,
            layout: layout, height: samplingHeight(layout: layout, target: targetHeight))
        return reduced(composed, layout: layout, height: targetHeight)
    }

    private static func reduced(_ render: RenderResult, layout: Layout, height: Int) -> RenderResult {
        let width = max(1, Int((Double(layout.width) * Double(height) / Double(layout.height)).rounded()))
        if render.image.height == height && render.image.width == width { return render }
        guard let image = Downsample.image(render.image, toHeight: height, width: width) else {
            return render
        }
        return RenderResult(image: image, layout: layout, profile: render.profile)
    }

    private static func samplingHeight(layout: Layout, target: Int) -> Int {
        min(layout.height, target * (Double(target) / Double(layout.height) < 0.2 ? 2 : 1))
    }

    public static func preview(of full: RenderResult, height: Int) -> RenderResult {
        guard height < full.image.height, let image = Downsample.image(full.image, toHeight: height) else {
            return full
        }
        return RenderResult(image: image, layout: full.layout, profile: full.profile)
    }

    private static func compose(
        source: SourceImage, recipe: Recipe, profile: ExportProfile, layout: Layout, height: Int
    ) throws -> RenderResult {
        try Task.checkCancellation()
        let space = profile.colorSpace
        let q = Double(height) / Double(layout.height)
        let W = max(1, Int((Double(layout.width) * q).rounded()))
        let H = height
        guard
            let ctx = CGContext(
                data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )
        else {
            throw PremiumShotError.renderFailed("The \(W) × \(H) bitmap could not be allocated.")
        }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        let look = Look.look(recipe)

        if let background = try BackgroundRaster.image(
            look: look, recipe: recipe, width: W, height: H, profile: profile, grainScale: q)
        {
            ctx.interpolationQuality = .high
            ctx.draw(background, in: CGRect(x: 0, y: 0, width: W, height: H))
            if q == 1 { try Grain.apply(to: ctx, opacity: Double(Grain.opacity)) }
        }
        try Task.checkCancellation()
        ctx.scaleBy(x: Double(W) / Double(layout.width), y: q)

        // Window geometry, converted from top-left pixels to CoreGraphics' bottom-left origin.
        let win = layout.window
        let windowRect = CGRect(
            x: win.x, y: layout.height - win.y - win.height, width: win.width, height: win.height)
        let radius = min(layout.cornerRadius, Double(min(win.width, win.height)) / 2)
        let windowPath = CGPath(
            roundedRect: windowRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        drawShadow(
            ctx, rect: windowRect, radius: radius, shadow: layout.ambientShadow, look: look, space: space,
            canvasWidth: layout.width, scale: q, scaleX: Double(W) / Double(layout.width))
        drawShadow(
            ctx, rect: windowRect, radius: radius, shadow: layout.keyShadow, look: look, space: space,
            canvasWidth: layout.width, scale: q, scaleX: Double(W) / Double(layout.width))

        // Screenshot clipped to its rounded rectangle.
        ctx.saveGState()
        ctx.addPath(windowPath)
        ctx.clip()
        let content = layout.content
        let contentRect = CGRect(
            x: content.x, y: layout.height - content.y - content.height, width: content.width,
            height: content.height)
        // At 1:1 the screenshot sits on the pixel grid and is copied without resampling so text stays crisp.
        ctx.interpolationQuality = layout.isPixelExact && q == 1 ? .none : .high
        ctx.draw(source.cgImage, in: contentRect)
        ctx.restoreGState()

        // 1 px hairline around the window.
        let hairline = 1.0
        ctx.setLineWidth(hairline)
        ctx.setStrokeColor(
            look.isDark
                ? CGColor(colorSpace: space, components: [1, 1, 1, 0.16])!
                : CGColor(colorSpace: space, components: [0, 0, 0, 0.11])!)
        let inset = hairline / 2
        ctx.addPath(
            CGPath(
                roundedRect: windowRect.insetBy(dx: inset, dy: inset), cornerWidth: max(0, radius - inset),
                cornerHeight: max(0, radius - inset), transform: nil))
        ctx.strokePath()

        try Task.checkCancellation()
        guard let image = ctx.makeImage() else {
            throw PremiumShotError.renderFailed("The bitmap could not be read back.")
        }
        return RenderResult(image: image, layout: layout, profile: profile)
    }

    /// The settled preview: the export render, area-averaged down to `height`. Because it is derived from
    /// the export, preview and file cannot disagree about composition or grain.
    public static func renderPreview(
        source: SourceImage, recipe: Recipe, profile: ExportProfile = .srgb, height: Int
    ) throws -> RenderResult {
        let full = try render(source: source, recipe: recipe, profile: profile)
        return preview(of: full, height: height)
    }

    // MARK: Drawing

    /// Draws only the shadow of a rounded rectangle. The casting shape is drawn far outside the canvas and
    /// its shadow is offset back, so no dark fill sits under the screenshot's anti-aliased corners.
    private static func drawShadow(
        _ ctx: CGContext, rect: CGRect, radius: Double, shadow: Layout.Shadow, look: Look,
        space: CGColorSpace, canvasWidth: Int, scale: Double, scaleX: Double
    ) {
        guard shadow.alpha > 0, shadow.blur >= 0 else { return }
        let away = Double(canvasWidth) * 4 + rect.width
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: away * scaleX, height: -shadow.offsetY * scale),
            blur: CGFloat(shadow.blur * scale),
            color: look.shadowTint.cgColor(in: space, alpha: shadow.alpha))
        ctx.setFillColor(CGColor(colorSpace: space, components: [0, 0, 0, 1])!)
        ctx.addPath(
            CGPath(
                roundedRect: rect.offsetBy(dx: -away, dy: 0), cornerWidth: radius, cornerHeight: radius,
                transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
    }
}

enum Downsample {
    /// Halves repeatedly while the image is more than twice the target, then resizes to the exact size.
    static func image(_ image: CGImage, toHeight targetHeight: Int, width: Int? = nil) -> CGImage? {
        let scale = Double(targetHeight) / Double(image.height)
        let targetWidth = width ?? max(1, Int((Double(image.width) * scale).rounded()))
        var current = image
        while current.height > targetHeight * 2 {
            guard
                let half = resize(
                    current, width: max(1, current.width / 2), height: max(1, current.height / 2))
            else { return nil }
            current = half
        }
        return resize(current, width: targetWidth, height: max(1, targetHeight))
    }

    private static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let space = image.colorSpace,
            let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
