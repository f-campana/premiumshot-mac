import CoreGraphics
import XCTest

@testable import PremiumShotCore

final class M1CoreTests: XCTestCase {
    func testPlacementAndContentRoundingForAdversarialShapes() {
        for (w, h) in [
            (200, 20000), (20000, 200), (1, 1), (50, 7000), (8000, 8000), (64_000_000, 1), (1, 64_000_000),
        ] {
            for shape in Shape.allCases {
                for space in 0...100 {
                    var r = Recipe.default
                    r.shape = shape
                    r.space = space
                    let l = LayoutEngine.resolve(sourceWidth: w, sourceHeight: h, recipe: r)
                    XCTAssertGreaterThanOrEqual(l.window.x, 0)
                    XCTAssertGreaterThanOrEqual(l.window.y, 0)
                    XCTAssertLessThanOrEqual(l.window.x + l.window.width, l.width)
                    XCTAssertLessThanOrEqual(l.window.y + l.window.height, l.height)
                    XCTAssertEqual(Double(l.content.height), Double(h) * l.screenshotScale, accuracy: 1)
                    XCTAssertGreaterThan(l.content.height, 0)
                }
            }
        }
    }
    func testShadowReallyDisappearsAndRampsSmoothly() throws {
        let ctx = CGContext(
            data: nil, width: 60, height: 40, bitsPerComponent: 8, bytesPerRow: 240,
            space: ExportProfile.srgb.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let source = SourceImage(cgImage: ctx.makeImage()!)
        for look in LookID.allCases {
            var r = Recipe.default
            r.look = look
            r.shadow = 0
            r.radius = 0
            let l = LayoutEngine.resolve(sourceWidth: 2560, sourceHeight: 1040, recipe: r)
            XCTAssertEqual(l.keyShadow.alpha, 0)
            XCTAssertEqual(l.ambientShadow.alpha, 0)
            r.shadow = 1
            let one = LayoutEngine.resolve(sourceWidth: 2560, sourceHeight: 1040, recipe: r)
            r.shadow = 10
            let ten = LayoutEngine.resolve(sourceWidth: 2560, sourceHeight: 1040, recipe: r)
            XCTAssertGreaterThan(one.keyShadow.alpha, 0)
            XCTAssertLessThan(one.keyShadow.alpha, ten.keyShadow.alpha)
        }
        var r = Recipe.default
        r.look = .clear
        r.shadow = 0
        r.radius = 0
        let result = try Renderer.render(source: source, recipe: r)
        let data = pixels(of: result.image)
        let c = result.layout.content
        for y in (c.y + 3)..<(c.y + c.height - 3) {
            for x in (c.x + 3)..<(c.x + c.width - 3) {
                XCTAssertEqual(pixel(data, width: result.image.width, x: x, y: y).a, 0)
            }
        }
    }
    func testDurationConversionAcrossSecondBoundaries() {
        for value in [0.0, 0.4, 1, 1.25, 2.5, 61] {
            XCTAssertEqual(Timing.milliseconds(.seconds(value)), value * 1000, accuracy: 0.1)
        }
    }
    func testZoomAnchorAndLimits() {
        var z = Zoom()
        z.configure(
            width: 2000, height: 2000, viewportWidth: 500, viewportHeight: 500, backingScale: 2, fit: true)
        XCTAssertEqual(z.scale, 0.5)
        z.zoom(to: 1)
        z.zoom(to: 2, anchorX: 100, anchorY: 80)
        XCTAssertEqual(z.x, -100)
        XCTAssertEqual(z.y, -80)
        z.zoom(to: 99)
        XCTAssertEqual(z.scale, 4)
        z.zoom(to: 0)
        XCTAssertEqual(z.scale, 0.5)
        XCTAssertEqual(z.x, 0)
        XCTAssertEqual(z.y, 0)
    }
}

extension M1CoreTests {
    func testSupersampledPreviewKeepsExactResolvedPixelDimensions() throws {
        let source = try Fixtures.source("tall-article.png")
        var recipe = Recipe.default
        recipe.look = .clear
        let layout = LayoutEngine.resolve(
            sourceWidth: source.width, sourceHeight: source.height, recipe: recipe)
        for height in [299, 300, 599, 600] {
            let fast = try Renderer.renderInteractive(source: source, recipe: recipe, height: height)
            let settled = try Renderer.renderPreview(source: source, recipe: recipe, height: height)
            XCTAssertEqual(fast.image.width, settled.image.width)
            XCTAssertEqual(fast.image.height, settled.image.height)
            XCTAssertEqual(fast.layout, layout)
            XCTAssertEqual(settled.layout, layout)
        }
    }
    func testInteractiveCompositionStaysCloseToSettledOutput() throws {
        var largestMean = 0.0
        var largestP99 = 0
        for fixture in [
            "small-dialog.png", "wide-dashboard.png", "tall-article.png", "thin-strip.png",
            "ultrawide-editor.png",
        ] {
            let source = try Fixtures.source(fixture)
            for look in LookID.allCases {
                for height in [300, 600] {
                    var recipe = Recipe.default
                    recipe.look = look
                    let fast = try Renderer.renderInteractive(source: source, recipe: recipe, height: height)
                    let settled = try Renderer.renderPreview(source: source, recipe: recipe, height: height)
                    let a = pixels(of: fast.image)
                    let b = pixels(of: settled.image)
                    XCTAssertEqual(a.count, b.count)
                    let diffs = zip(a, b).map { abs(Int($0) - Int($1)) }.sorted()
                    let mean = Double(diffs.reduce(0, +)) / Double(diffs.count)
                    let p99 = diffs[Int(Double(diffs.count - 1) * 0.99)]
                    largestMean = max(largestMean, mean)
                    largestP99 = max(largestP99, p99)
                    print("preview-diff \(fixture) \(look) height=\(height): mean=\(mean) p99=\(p99)")
                    XCTAssertLessThanOrEqual(mean, 2.5, "\(fixture) \(look)")
                    XCTAssertLessThanOrEqual(p99, 40, "\(fixture) \(look)")
                }
            }
        }
        print("preview-diff maximum mean=\(largestMean) p99=\(largestP99)")
    }
    func testShadowBorderAtMaximumAndDefaultAcrossShapes() throws {
        for fixture in ["thin-strip.png", "small-dialog.png", "tall-article.png"] {
            let source = try Fixtures.source(fixture)
            for shape in Shape.allCases {
                for shadow in [0, 1, 9, 10, 55, 100] {
                    var r = Recipe.default
                    r.look = .clear
                    r.shape = shape
                    r.shadow = shadow
                    let result = try Renderer.render(source: source, recipe: r)
                    let w = result.image.width
                    let h = result.image.height
                    // The renderer emits premultiplied RGBA. Inspect its border directly;
                    // copying millions of interior pixels would dominate this exhaustive sweep.
                    let data = try XCTUnwrap(result.image.dataProvider?.data)
                    let p = try XCTUnwrap(CFDataGetBytePtr(data))
                    XCTAssertEqual(result.image.alphaInfo, .premultipliedLast)
                    let stride = result.image.bytesPerRow
                    var worst = 0
                    for x in 0..<w {
                        worst = max(worst, Int(p[x * 4 + 3]), Int(p[(h - 1) * stride + x * 4 + 3]))
                    }
                    for y in 0..<h {
                        worst = max(worst, Int(p[y * stride + 3]), Int(p[y * stride + (w - 1) * 4 + 3]))
                    }
                    XCTAssertLessThanOrEqual(worst, 3, "\(fixture) \(shape) \(shadow)")
                }
            }
        }
    }
    func testSmallInspectCanReachActualSizeEvenWhenFitEnlarges() {
        var zoom = Zoom()
        zoom.configure(
            width: 200, height: 100, viewportWidth: 800, viewportHeight: 500,
            backingScale: 2, fit: true)
        XCTAssertEqual(zoom.scale, 4)
        zoom.zoom(to: 1)
        XCTAssertEqual(zoom.scale, 1)
    }
}

extension M1CoreTests {
    func testExtremeFitCropsKeepTheCanvasBorderClear() throws {
        for (width, height) in [(200, 20000), (20000, 200), (1, 100000), (100000, 1)] {
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: ExportProfile.srgb.colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.setFillColor(CGColor(gray: 0.7, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let source = SourceImage(cgImage: context.makeImage()!)
            for shadow in [0, 1, 9, 10, 55, 100] {
                var recipe = Recipe.default
                recipe.look = .clear
                recipe.shadow = shadow
                let result = try Renderer.render(source: source, recipe: recipe)
                let image = result.image
                let data = try XCTUnwrap(image.dataProvider?.data)
                let p = try XCTUnwrap(CFDataGetBytePtr(data))
                let stride = image.bytesPerRow
                var alpha = 0
                for x in 0..<image.width {
                    alpha = max(alpha, Int(p[x * 4 + 3]), Int(p[(image.height - 1) * stride + x * 4 + 3]))
                }
                for y in 0..<image.height {
                    alpha = max(
                        alpha, Int(p[y * stride + 3]), Int(p[y * stride + (image.width - 1) * 4 + 3]))
                }
                XCTAssertLessThanOrEqual(alpha, 3, "\(width)×\(height) shadow \(shadow)")
            }
        }
    }
    func testFusedGrainMatchesQuartzOverlayWithinOneCodeValue() throws {
        for value in [20, 100, 128, 235] {
            func bitmap() -> CGContext {
                let ctx = CGContext(
                    data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 800,
                    space: ExportProfile.srgb.colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue)!
                ctx.setFillColor(CGColor(gray: Double(value) / 255, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
                return ctx
            }
            let direct = bitmap()
            let quartz = bitmap()
            try Grain.apply(to: direct, opacity: 0.13)
            quartz.setBlendMode(.overlay)
            quartz.setAlpha(0.13)
            quartz.draw(
                Grain.image(width: 200, height: 100, space: ExportProfile.srgb.colorSpace)!,
                in: CGRect(x: 0, y: 0, width: 200, height: 100))
            let a = pixels(of: direct.makeImage()!)
            let b = pixels(of: quartz.makeImage()!)
            XCTAssertLessThanOrEqual(zip(a, b).map { abs(Int($0) - Int($1)) }.max()!, 1)
        }
    }
}
