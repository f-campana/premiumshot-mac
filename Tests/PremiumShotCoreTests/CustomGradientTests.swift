import CoreGraphics
import Foundation
import XCTest

@testable import PremiumShotCore

final class CustomGradientTests: XCTestCase {
    static let hues = [0, 60, 120, 180, 240, 300, 359]
    static let edgePairs = [(350, 10), (359, 0), (0, 360), (155, 155), (0, 180), (90, 270)]

    func testPublishedColourReferenceAndRoundTrips() {
        let red = LinearRGB(r: 1, g: 0, b: 0).lab
        XCTAssertEqual(red.l, 0.62795536, accuracy: 0.0000001)
        XCTAssertEqual(red.a, 0.22486306, accuracy: 0.0000001)
        XCTAssertEqual(red.b, 0.12584630, accuracy: 0.0000001)
        for rgb in [
            LinearRGB(r: 1, g: 0, b: 0), LinearRGB(r: 0, g: 1, b: 0),
            LinearRGB(r: 0, g: 0, b: 1), LinearRGB(r: 1, g: 1, b: 1),
            LinearRGB(r: 0.12, g: 0.53, b: 0.87),
        ] {
            let roundTrip = rgb.lab.linearRGB
            XCTAssertEqual(roundTrip.r, rgb.r, accuracy: 0.0000003)
            XCTAssertEqual(roundTrip.g, rgb.g, accuracy: 0.0000003)
            XCTAssertEqual(roundTrip.b, rgb.b, accuracy: 0.0000003)
        }
    }

    func testSamplerLightnessHueAndGamutBeforeShadingAcrossContactSheet() {
        let pairs = Self.hues.flatMap { a in Self.hues.map { (a, $0) } } + Self.edgePairs
        for (from, to) in pairs {
            let sampler = GradientSampler(from: from, to: to)
            let start = OKLab(hue: from)
            let end = OKLab(hue: to)
            for step in 0...256 {
                let t = Double(step) / 256
                let rgb = sampler.sample(t)
                let lab = rgb.lab
                let expected = start.blended(to: end, at: t)
                XCTAssertTrue(rgb.inGamut, "\(from)/\(to) at \(t)")
                XCTAssertEqual(lab.l, CustomGradient.lightness, accuracy: 0.000005)
                XCTAssertLessThanOrEqual(lab.chroma, expected.chroma + 0.000005)
                if expected.chroma > 0.02 {
                    let delta = abs(lab.hue - expected.hue)
                    XCTAssertLessThan(min(delta, 360 - delta), 0.01)
                }
                let shaded = rgb.shaded(by: CustomGradient.minimumIntensity).lab
                XCTAssertLessThanOrEqual(lab.l - shaded.l, CustomGradient.shadingLightnessBound + 0.000005)
            }
        }
        let opposite = GradientSampler(from: 0, to: 180).sample(0.5).lab
        XCTAssertLessThan(
            opposite.chroma, 0.000001, "Opposing hues have a neutral middle, without hue-path switching")
        XCTAssertEqual(GradientSampler.endpoint(0), GradientSampler.endpoint(360))
        let wrap = GradientSampler(from: 350, to: 10).sample(0.5).lab
        XCTAssertLessThan(min(wrap.hue, 360 - wrap.hue), 0.01)
    }

    func testBackgroundUsesSamplerAtSpatialPositionAndIsOpaque() throws {
        let image = try CustomGradient.image(width: 113, height: 79, from: 0, to: 180)
        let bytes = pixels(of: image)
        let sampler = GradientSampler(from: 0, to: 180)
        for (x, y) in [(0, 0), (112, 0), (0, 78), (112, 78), (56, 39), (13, 57)] {
            let field = CustomGradient.field(x: Double(x) + 0.5, y: Double(y) + 0.5, width: 113, height: 79)
            let expected = sampler.sample(field.t).shaded(by: field.intensity).srgb
            let actual = pixel(bytes, width: 113, x: x, y: y)
            XCTAssertEqual(actual.r, Int((expected.r * 255).rounded()), accuracy: 1)
            XCTAssertEqual(actual.g, Int((expected.g * 255).rounded()), accuracy: 1)
            XCTAssertEqual(actual.b, Int((expected.b * 255).rounded()), accuracy: 1)
            XCTAssertEqual(actual.a, 255)
        }
        for i in stride(from: 3, to: bytes.count, by: 4) { XCTAssertEqual(bytes[i], 255) }
    }

    func testShadingLookupMatchesDirectTransferAndMappingDoesNotClipChannels() {
        for hue in Self.hues {
            let sampler = GradientSampler(from: hue, to: (hue + 120) % 360)
            for step in 0...256 {
                let t = Double(step) / 256
                let intensity = 0.97 + 0.03 * t
                let exact = sampler.sample(t).shaded(by: intensity).srgb
                let fast = sampler.sampleShaded(t, intensity: intensity)
                XCTAssertEqual(fast.r, exact.r, accuracy: 0.00002)
                XCTAssertEqual(fast.g, exact.g, accuracy: 0.00002)
                XCTAssertEqual(fast.b, exact.b, accuracy: 0.00002)
            }
        }
        let outside = OKLab(hue: 180)
        XCTAssertFalse(outside.linearRGB.inGamut)
        let mapped = outside.gamutMapped.lab
        XCTAssertEqual(mapped.l, outside.l, accuracy: 0.000001)
        XCTAssertLessThan(mapped.chroma, outside.chroma)
        XCTAssertFalse(
            OKLab(l: mapped.l, a: mapped.a * 1.001, b: mapped.b * 1.001).linearRGB.inGamut,
            "Mapping ends at the gamut boundary by reducing chroma")
        let clipped = outside.linearRGB
        let clippedLab = LinearRGB(
            r: min(1, max(0, clipped.r)), g: min(1, max(0, clipped.g)), b: min(1, max(0, clipped.b))
        ).lab
        XCTAssertGreaterThan(abs(clippedLab.l - outside.l), 0.001, "Clipping cannot stand in for this mapper")
    }

    func testHueCacheInvalidationAndReuse() throws {
        var recipe = Recipe(look: .custom)
        func background(_ r: Recipe) throws -> CGImage {
            try XCTUnwrap(
                BackgroundRaster.image(
                    look: Look.look(r), recipe: r,
                    width: 97, height: 65, profile: .srgb, grainScale: 1))
        }
        let first = try background(recipe)
        recipe.radius = 80
        recipe.shadow = 10
        XCTAssertTrue(first === (try background(recipe)), "Geometry edits reuse the colour field")
        recipe.gradientFrom = 30
        let changed = try background(recipe)
        XCTAssertFalse(first === changed)
        XCTAssertNotEqual(pixels(of: first), pixels(of: changed))
        XCTAssertTrue(changed === (try background(recipe)))
        recipe.gradientFrom = 360
        let wrap = try background(recipe)
        recipe.gradientFrom = 0
        XCTAssertTrue(wrap === (try background(recipe)), "360 and 0 have one cache identity")
    }

    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }
    struct Maximum: RandomNumberGenerator {
        var calls = 0
        mutating func next() -> UInt64 {
            calls += 1
            return .max
        }
    }
    func testRandomizerCircularRulesAndBoundedFallback() {
        var rng = Seeded(state: 42)
        var previous = GradientHues(from: 350, to: 10)
        for _ in 0..<2000 {
            let next = previous.randomized(using: &rng)
            XCTAssertTrue((0..<360).contains(next.from) && (0..<360).contains(next.to))
            XCTAssertTrue((40...140).contains(GradientHues.distance(next.from, next.to)))
            XCTAssertTrue(
                GradientHues.distance(previous.from, next.from) >= 30
                    || GradientHues.distance(previous.to, next.to) >= 30)
            previous = next
        }
        var a = Seeded(state: 99)
        var b = Seeded(state: 99)
        XCTAssertEqual(previous.randomized(using: &a), previous.randomized(using: &b))
        var probe = Maximum()
        let repeated = GradientHues(from: 0, to: 0).randomized(using: &probe)
        var maximum = Maximum()
        let fallback = repeated.randomized(using: &maximum)
        XCTAssertLessThanOrEqual(maximum.calls, 96)
        XCTAssertEqual(maximum.calls, 96, "All 32 repeated candidates reach the fallback")
        XCTAssertTrue((40...140).contains(GradientHues.distance(fallback.from, fallback.to)))
        XCTAssertTrue(GradientHues.distance(repeated.from, fallback.from) >= 30)
    }

    /// Opt-in review artifact, generated through the shipped renderer, never a second colour implementation.
    func testWriteContactSheetCellsWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["M12_CONTACT_DIR"] else { return }
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = try Fixtures.source("small-dialog.png")
        var manifest: [[String: Any]] = []
        let pairs = Self.hues.flatMap { a in Self.hues.map { (a, $0) } } + Self.edgePairs
        for (index, pair) in pairs.enumerated() {
            let recipe = Recipe(look: .custom, shape: .wide, gradientFrom: pair.0, gradientTo: pair.1)
            let render = try Renderer.renderInteractive(source: source, recipe: recipe, height: 120)
            let name = String(format: "%02d-%03d-%03d.png", index, pair.0, pair.1)
            try PNG.encode(render.image).write(to: folder.appendingPathComponent(name))
            manifest.append(["file": name, "from": pair.0, "to": pair.1])
        }
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("manifest.json"))
    }
}
