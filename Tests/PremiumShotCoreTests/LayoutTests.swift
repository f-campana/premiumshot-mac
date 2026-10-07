import XCTest
@testable import PremiumShotCore

final class LayoutTests: XCTestCase {
    func resolve(_ w: Int, _ h: Int, _ configure: (inout Recipe) -> Void = { _ in }) -> Layout {
        var r = Recipe.default; configure(&r)
        return LayoutEngine.resolve(sourceWidth: w, sourceHeight: h, recipe: r)
    }

    /// The mock showed "2789 × 1269 px" for the wide sample at the defaults.
    func testFitMatchesTheMockReadout() {
        let l = resolve(2560, 1040)
        XCTAssertEqual(l.width, 2789); XCTAssertEqual(l.height, 1269)
        XCTAssertEqual(l.screenshotScale, 1); XCTAssertFalse(l.capped)
    }

    func testFixedShapesUseTheSpecifiedCanvas() {
        for (shape, size) in [(Shape.wide, (1920, 1080)), (.portrait, (1080, 1350)), (.square, (1080, 1080)), (.link, (1200, 630))] {
            let l = resolve(2560, 1040) { $0.shape = shape }
            XCTAssertEqual(l.width, size.0, "\(shape)"); XCTAssertEqual(l.height, size.1, "\(shape)")
            XCTAssertFalse(l.capped)
        }
    }

    // R3: the long edge never exceeds 4096, and "capped" is true exactly when it was reduced.
    func testCapAppliesToTheLongEdgeAndIsFlaggedExactly() {
        let tall = resolve(1520, 4262)
        XCTAssertEqual(tall.height, 4096); XCTAssertTrue(tall.capped); XCTAssertLessThan(tall.screenshotScale, 1)
        let notCapped = resolve(3440, 1440)   // 3440 + 2 × 158 = 3756 < 4096
        XCTAssertFalse(notCapped.capped); XCTAssertLessThanOrEqual(max(notCapped.width, notCapped.height), 4096)
        for (w, h) in [(5000, 1000), (1000, 7000), (4096, 100), (100, 4096), (2000, 2000), (50, 50)] {
            for space in [0, 50, 100] {
                let l = resolve(w, h) { $0.space = space }
                XCTAssertLessThanOrEqual(max(l.width, l.height), 4096, "\(w)x\(h) space \(space)")
            }
        }
        // Exactly at the threshold: Fit with zero margin pushes a 4096-wide source over by the margin, so it is capped.
        XCTAssertTrue(resolve(4096, 100).capped)
        XCTAssertFalse(resolve(2000, 2000).capped)
    }

    // R6: the screenshot is never enlarged.
    func testScreenshotIsNeverEnlarged() {
        for shape in Shape.allCases { for frame in Frame.allCases { for (w, h) in [(60, 40), (420, 280), (880, 608), (2560, 1040), (1520, 4262), (3440, 160)] {
            for space in [0, 50, 100] {
                let l = resolve(w, h) { $0.shape = shape; $0.frame = frame; $0.space = space }
                XCTAssertLessThanOrEqual(l.screenshotScale, 1 + 1e-12, "\(shape) \(frame) \(w)x\(h) space \(space)")
            }
        } } }
    }

    // Geometry the renderer relies on.
    func testWindowStaysInsideTheCanvasAndKeepsTheSourceSizeAtOneToOne() {
        for frame in Frame.allCases {
            let l = resolve(880, 608) { $0.frame = frame }
            XCTAssertTrue(l.isPixelExact)
            XCTAssertEqual(l.content.width, 880); XCTAssertEqual(l.content.height, 608)
            XCTAssertEqual(l.bar, frame.barHeight)
            XCTAssertGreaterThanOrEqual(l.window.x, 0); XCTAssertGreaterThanOrEqual(l.window.y, 0)
            XCTAssertLessThanOrEqual(l.window.x + l.window.width, l.width)
            XCTAssertLessThanOrEqual(l.window.y + l.window.height, l.height)
        }
        for shape in Shape.allCases {
            let l = resolve(2560, 1040) { $0.shape = shape; $0.frame = .browser }
            XCTAssertGreaterThanOrEqual(l.window.x, 0); XCTAssertGreaterThanOrEqual(l.window.y, 0)
            XCTAssertLessThanOrEqual(l.window.x + l.window.width, l.width)
            XCTAssertLessThanOrEqual(l.window.y + l.window.height, l.height)
        }
    }

    func testSpaceControlsTheMarginMonotonically() {
        let tight = resolve(880, 608) { $0.space = 0 }, loose = resolve(880, 608) { $0.space = 100 }
        XCTAssertLessThan(tight.width, loose.width)
    }

    func testShadowGrowsWithTheSliderAndVanishesAtZero() {
        let none = resolve(880, 608) { $0.shadow = 0 }, some = resolve(880, 608) { $0.shadow = 100 }
        XCTAssertEqual(none.keyShadow.blur, 0); XCTAssertGreaterThan(some.keyShadow.blur, 0)
        XCTAssertGreaterThan(some.ambientShadow.blur, some.keyShadow.blur)
    }
}
