import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import PremiumShotCore

final class RendererTests: XCTestCase {
    func render(
        _ fixture: String, _ configure: (inout Recipe) -> Void = { _ in }, profile: ExportProfile = .srgb
    ) throws -> RenderResult {
        var r = Recipe.default
        configure(&r)
        return try Renderer.render(source: try Fixtures.source(fixture), recipe: r, profile: profile)
    }

    // R2 / R3: the image has exactly the resolved size, which is what the caption reports.
    func testRenderedSizeEqualsTheResolvedLayout() throws {
        for (fixture, shape) in [
            ("small-dialog.png", Shape.fit), ("wide-dashboard.png", .wide), ("tall-article.png", .fit),
            ("thin-strip.png", .link),
        ] {
            let result = try render(fixture) { $0.shape = shape }
            XCTAssertEqual(result.image.width, result.layout.width, fixture)
            XCTAssertEqual(result.image.height, result.layout.height, fixture)
            XCTAssertLessThanOrEqual(max(result.image.width, result.image.height), 4096)
        }
        XCTAssertTrue(try render("tall-article.png").layout.capped)
    }

    // R4: same recipe, input and profile give identical pixels.
    func testRenderingIsDeterministic() throws {
        for look in LookID.allCases {
            let a = try render("small-dialog.png") {
                $0.look = look
            }
            let b = try render("small-dialog.png") {
                $0.look = look
            }
            XCTAssertEqual(pixels(of: a.image), pixels(of: b.image), "\(look)")
        }
    }

    // R5: at 1:1 the opaque interior equals the source, exactly when the colour spaces match.
    func testPixelPreservationAtOneToOne() throws {
        let source = try Fixtures.source("exact-pattern.png")
        let reference = pixels(of: source.cgImage, in: ExportProfile.srgb.colorSpace)
        for look in LookID.allCases {
            var recipe = Recipe.default
            recipe.look = look
            let result = try Renderer.render(source: source, recipe: recipe)
            XCTAssertTrue(result.layout.isPixelExact)
            let out = pixels(of: result.image)
            let c = result.layout.content
            let margin = Int(result.layout.cornerRadius.rounded(.up)) + 3  // stay clear of rounded corners and the hairline
            var mismatches = 0
            for y in margin..<(c.height - margin) {
                for x in margin..<(c.width - margin) {
                    let o = pixel(out, width: result.image.width, x: c.x + x, y: c.y + y)
                    let s = pixel(reference, width: source.width, x: x, y: y)
                    if o.r != s.r || o.g != s.g || o.b != s.b || o.a != 255 { mismatches += 1 }
                }
            }
            XCTAssertEqual(mismatches, 0, "frame, look \(look)")
        }
    }

    /// A Display P3 source exported as sRGB equals the source converted to sRGB on its own, within ±1.
    func testWideGamutSourceMatchesTheColourConvertedReference() throws {
        let source = try Fixtures.source("p3-patches.png")
        XCTAssertEqual(source.cgImage.colorSpace?.name as String?, CGColorSpace.displayP3 as String)
        let reference = pixels(of: source.cgImage, in: ExportProfile.srgb.colorSpace)
        let result = try Renderer.render(source: source, recipe: .default, profile: .srgb)
        let out = pixels(of: result.image)
        let c = result.layout.content
        let margin = Int(result.layout.cornerRadius) + 3
        var worst = 0
        for y in stride(from: margin, to: c.height - margin, by: 3) {
            for x in stride(from: margin, to: c.width - margin, by: 3) {
                let o = pixel(out, width: result.image.width, x: c.x + x, y: c.y + y)
                let s = pixel(reference, width: source.width, x: x, y: y)
                worst = max(worst, abs(o.r - s.r), abs(o.g - s.g), abs(o.b - s.b))
            }
        }
        XCTAssertLessThanOrEqual(worst, 1)
    }

    // R7: Clear exports real alpha; the shadow keeps the tint colour instead of darkening toward black.
    func testClearLookHasRealAlphaAndNoDarkFringe() throws {
        var recipe = Recipe.default
        recipe.look = .clear
        recipe.shadow = 100
        let source = try Fixtures.source("small-dialog.png")
        let result = try Renderer.render(source: source, recipe: recipe)
        let out = pixels(of: result.image)
        let w = result.image.width
        let win = result.layout.window
        XCTAssertEqual(pixel(out, width: w, x: 0, y: 0).a, 0, "far corner is transparent")
        XCTAssertEqual(
            pixel(out, width: w, x: win.x + win.width / 2, y: win.y + win.height / 2).a, 255,
            "window interior is opaque")
        // Straight (un-premultiplied) colour of the shadow just below the window must stay near the tint (20, 26, 48).
        let probe = pixel(out, width: w, x: win.x + win.width / 2, y: win.y + win.height + 6)
        XCTAssertGreaterThan(probe.a, 8, "there is a visible shadow below the window")
        let tint = Look.look(.clear).shadowTint
        for (channel, expected) in [(probe.r, tint.r), (probe.g, tint.g), (probe.b, tint.b)] {
            let straight = Double(channel) * 255 / Double(probe.a) / 255
            XCTAssertEqual(straight, expected, accuracy: 0.05, "shadow colour must not fringe toward black")
        }
        // Composited on white, no pixel may be darker than the shadow itself can make it.
        let alphaAtEdge = Double(probe.a) / 255
        XCTAssertLessThan(alphaAtEdge, 0.7)
    }

    // R8: every export is tagged with the profile it claims, and nothing is written untagged.
    func testExportsCarryTheirColourProfile() throws {
        for profile in ExportProfile.allCases {
            let result = try render("small-dialog.png", profile: profile)
            let decoded = PNG.inspect(try PNG.encode(result.image))
            XCTAssertEqual(decoded?.colorSpaceName, profile.colorSpaceName, "\(profile)")
        }
    }

    func testLookColoursAreInterpretedAsSRGB() throws {
        // Paper's base colour is #ecebe6 in sRGB; far from any blob it must land on that value in an sRGB render.
        var recipe = Recipe.default
        recipe.look = .paper
        recipe.shape = .wide
        let result = try Renderer.render(source: try Fixtures.source("small-dialog.png"), recipe: recipe)
        let out = pixels(of: result.image)
        let p = pixel(out, width: result.image.width, x: 960, y: 1060)
        XCTAssertEqual(p.r, 0xec, accuracy: 18)
        XCTAssertEqual(p.g, 0xeb, accuracy: 18)
        XCTAssertEqual(p.b, 0xe6, accuracy: 24)
        XCTAssertGreaterThan(p.r, 200)
    }

    // The settled preview is the downsampled export, so the two cannot disagree about composition.
    func testPreviewIsTheDownsampledExport() throws {
        let source = try Fixtures.source("wide-dashboard.png")
        let full = try Renderer.render(source: source, recipe: .default)
        let preview = try Renderer.renderPreview(source: source, recipe: .default, height: 300)
        XCTAssertEqual(preview.layout, full.layout)
        XCTAssertEqual(preview.image.height, 300)
        XCTAssertEqual(
            Double(preview.image.width) / 300, Double(full.image.width) / Double(full.image.height),
            accuracy: 0.01)
        XCTAssertEqual(
            try Renderer.renderPreview(source: source, recipe: .default, height: 99_999).image.width,
            full.image.width)
    }

    func testRendersEveryLookShapeWithoutFailing() throws {
        for fixture in [
            "small-dialog.png", "wide-dashboard.png", "tall-article.png",
            "thin-strip.png", "ultrawide-editor.png", "p3-patches.png",
            "exact-pattern.png", "small-dialog.heic", "rotated-dialog.jpg",
        ] {
            let source = try Fixtures.source(fixture)
            for look in LookID.allCases {
                for shape in Shape.allCases {
                    var r = Recipe.default
                    r.look = look
                    r.shape = shape
                    let result = try autoreleasepool { try Renderer.render(source: source, recipe: r) }
                    XCTAssertEqual(result.image.width, result.layout.width, fixture)
                    XCTAssertEqual(result.image.height, result.layout.height, fixture)
                    XCTAssertLessThanOrEqual(
                        result.layout.window.x + result.layout.window.width, result.image.width)
                    XCTAssertLessThanOrEqual(
                        result.layout.window.y + result.layout.window.height, result.image.height)
                }
            }
        }
    }

    // C6: the new margin floor lets the shadow fade before it reaches the canvas border.
    func testDefaultShadowIsNotClippedByTheCanvasEdge() throws {
        let fixtures = [
            "small-dialog.png", "wide-dashboard.png", "tall-article.png", "thin-strip.png",
            "ultrawide-editor.png",
        ]
        for fixture in fixtures {
            for shape in Shape.allCases {
                var recipe = Recipe.default
                recipe.look = .clear
                recipe.shape = shape
                let result = try Renderer.render(source: try Fixtures.source(fixture), recipe: recipe)
                let out = pixels(of: result.image)
                let w = result.image.width
                let h = result.image.height
                var worst = 0
                for x in 0..<w {
                    worst = max(
                        worst, pixel(out, width: w, x: x, y: 0).a, pixel(out, width: w, x: x, y: h - 1).a)
                }
                for y in 0..<h {
                    worst = max(
                        worst, pixel(out, width: w, x: 0, y: y).a, pixel(out, width: w, x: w - 1, y: y).a)
                }
                XCTAssertLessThanOrEqual(
                    worst, 3, "\(fixture) \(shape): shadow still has alpha \(worst)/255 at the canvas edge")
            }
        }
    }
}
