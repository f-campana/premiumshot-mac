import CoreGraphics
import XCTest

@testable import PremiumShotCore

final class M11GeometryTests: XCTestCase {
    private let sources = [
        (2560, 1040), (1520, 4262), (880, 608), (3440, 160),
        (3024, 1964), (200, 20000), (20, 20), (1, 1), (1, 100000),
    ]
    private func signature(_ l: Layout) -> [Double] {
        [
            Double(l.width), Double(l.height), l.capped ? 1 : 0, l.screenshotScale,
            Double(l.window.x), Double(l.window.y), Double(l.window.width), Double(l.window.height),
            l.cornerRadius,
        ]
    }
    func testLookAndShadowLeaveAllGeometryUnchanged() {
        for (w, h) in sources {
            for shape in Shape.allCases {
                for space in [0, 50, 100] {
                    var r = Recipe.default
                    r.shape = shape
                    r.space = space
                    let expected = signature(
                        LayoutEngine.resolve(sourceWidth: w, sourceHeight: h, recipe: r))
                    for look in LookID.allCases {
                        r.look = look
                        for shadow in 0...100 {
                            r.shadow = shadow
                            XCTAssertEqual(
                                signature(
                                    LayoutEngine.resolve(sourceWidth: w, sourceHeight: h, recipe: r)),
                                expected)
                        }
                    }
                }
            }
        }
    }
    func testContinuousSpaceAndRoundedGeometryMoveWithoutReversals() {
        for (w, h) in sources {
            for shape in Shape.allCases {
                var measures: [Double] = []
                var raster: [Double] = []
                for space in 0...100 {
                    var r = Recipe.default
                    r.shape = shape
                    r.space = space
                    r.shadow = 100
                    let c = LayoutEngine.continuous(sourceWidth: w, sourceHeight: h, recipe: r)
                    let l = LayoutEngine.resolve(sourceWidth: w, sourceHeight: h, recipe: r)
                    measures.append(shape == .fit ? c.margin : -c.scale)
                    raster.append(
                        shape == .fit
                            ? 1 - Double(l.window.width) / Double(l.width) : -Double(l.window.height))
                    XCTAssertGreaterThan(l.screenshotScale, 0)
                    XCTAssertLessThanOrEqual(l.screenshotScale, 1)
                    XCTAssertGreaterThanOrEqual(l.window.x, 2)
                    XCTAssertGreaterThanOrEqual(l.window.y, 2)
                    XCTAssertGreaterThanOrEqual(l.width - l.window.x - l.window.width, 2)
                    XCTAssertGreaterThanOrEqual(l.height - l.window.y - l.window.height, 2)
                    XCTAssertGreaterThan(l.content.height, 0)
                }
                let span = measures.last! - measures.first!
                XCTAssertGreaterThan(span, 0)
                for i in 1..<measures.count {
                    XCTAssertGreaterThan(measures[i], measures[i - 1])
                    XCTAssertLessThanOrEqual(measures[i] - measures[i - 1], span * 0.03)
                    XCTAssertGreaterThanOrEqual(
                        raster[i] + 1e-12, raster[i - 1], "\(w)x\(h) \(shape) Space \(i)")
                }
            }
        }
    }
    func testUndersizedFixedSourceIsPositiveAndNeverEnlarged() {
        for w in [1, 20, 200] {
            var r = Recipe.default
            r.shape = .square
            for (space, expected) in [(0, 1.0), (50, 0.85), (100, 0.7)] {
                r.space = space
                let l = LayoutEngine.resolve(sourceWidth: w, sourceHeight: w, recipe: r)
                XCTAssertEqual(l.screenshotScale, expected, accuracy: 1e-12)
            }
        }
    }
    func testSpaceEndpointsHaveAVisibleEffectAtMaximumShadow() {
        for (w, h) in sources where min(w, h) >= 200 {
            for shape in Shape.allCases {
                var r = Recipe.default
                r.shape = shape
                r.shadow = 100
                r.space = 0
                let tight = LayoutEngine.resolve(sourceWidth: w, sourceHeight: h, recipe: r)
                r.space = 100
                let roomy = LayoutEngine.resolve(sourceWidth: w, sourceHeight: h, recipe: r)
                let widthChange =
                    Double(tight.window.width) / Double(tight.width)
                    - Double(roomy.window.width) / Double(roomy.width)
                let heightChange =
                    Double(tight.window.height) / Double(tight.height)
                    - Double(roomy.window.height) / Double(roomy.height)
                XCTAssertGreaterThanOrEqual(
                    max(widthChange, heightChange), 0.05,
                    "\(w)x\(h) \(shape)")
            }
        }
    }
    func testDefaultKeyShadowDoesNotNeedToShrink() {
        let l = LayoutEngine.resolve(sourceWidth: 2560, sourceHeight: 1040, recipe: .default)
        XCTAssertEqual([l.width, l.height], [2789, 1269])
        XCTAssertEqual(l.keyShadow.blur, sqrt(2560.0 * 1040) * 0.05 * 0.55 * 0.8, accuracy: 1e-8)
    }
    func testTightSpaceMaxShadowKeepsActualTransparentBordersClear() throws {
        for (w, h) in [(20, 20), (200, 20000), (20000, 200), (1, 100000)] {
            let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: ExportProfile.srgb.colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )!
            ctx.setFillColor(CGColor(gray: 0.7, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let source = SourceImage(cgImage: ctx.makeImage()!)
            for shape in [Shape.fit, .wide, .square] {
                var r = Recipe.default
                r.look = .clear
                r.space = 0
                r.shadow = 100
                r.shape = shape
                let image = try Renderer.render(source: source, recipe: r).image
                let data = try XCTUnwrap(image.dataProvider?.data)
                let p = try XCTUnwrap(CFDataGetBytePtr(data))
                var worst = 0
                for x in 0..<image.width {
                    worst = max(
                        worst, Int(p[x * 4 + 3]),
                        Int(p[(image.height - 1) * image.bytesPerRow + x * 4 + 3]))
                }
                for y in 0..<image.height {
                    worst = max(
                        worst, Int(p[y * image.bytesPerRow + 3]),
                        Int(p[y * image.bytesPerRow + (image.width - 1) * 4 + 3]))
                }
                XCTAssertLessThanOrEqual(worst, 3, "\(w)x\(h) \(shape)")
            }
        }
    }
}
