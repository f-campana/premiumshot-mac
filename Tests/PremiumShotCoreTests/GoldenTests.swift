import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PremiumShotCore

/// Golden images guard against accidental changes to the look of the output.
///
/// Each golden is the **settled preview** (the export, area-averaged to 200 px high), so grain averages out and
/// files stay small. Comparison is tolerant because Core Graphics may shift by a code value or two across macOS
/// releases. To accept an intentional change, run: UPDATE_GOLDENS=1 swift test --filter GoldenTests
final class GoldenTests: XCTestCase {
    static let directory = Fixtures.url("golden")
    /// A pixel differs if any channel is off by more than this many code values.
    static let channelTolerance = 3
    /// At most this fraction of pixels may differ.
    static let allowedFraction = 0.002

    struct Case { let name: String; let fixture: String; let recipe: Recipe }
    static let cases: [Case] = {
        var list: [Case] = Look.all.map { $0.id }.map { look in
            var r = Recipe.default; r.look = look
            return Case(name: "dialog-\(look.rawValue)-fit", fixture: "small-dialog.png", recipe: r)
        }
        var tall = Recipe.default; tall.shape = .portrait; tall.look = .paper
        list.append(Case(name: "article-paper-4x5", fixture: "tall-article.png", recipe: tall))
        return list
    }()

    func testGoldens() throws {
        let update = ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1"
        if update { try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true) }
        for c in Self.cases {
            let result = try Renderer.renderPreview(source: try Fixtures.source(c.fixture), recipe: c.recipe, height: 200)
            let url = Self.directory.appendingPathComponent(c.name + ".png")
            if update { try PNG.write(try PNG.encode(result.image), to: url); continue }
            guard let data = FileManager.default.contents(atPath: url.path), let golden = PNG.inspect(data)?.image else {
                XCTFail("missing golden \(c.name).png: run UPDATE_GOLDENS=1 swift test --filter GoldenTests"); continue
            }
            XCTAssertEqual([golden.width, golden.height], [result.image.width, result.image.height], c.name)
            guard golden.width == result.image.width, golden.height == result.image.height else { continue }
            let a = pixels(of: golden, in: ExportProfile.srgb.colorSpace), b = pixels(of: result.image, in: ExportProfile.srgb.colorSpace)
            var differing = 0
            for i in stride(from: 0, to: a.count, by: 4) where (0..<4).contains(where: { abs(Int(a[i + $0]) - Int(b[i + $0])) > Self.channelTolerance }) { differing += 1 }
            let fraction = Double(differing) / Double(a.count / 4)
            XCTAssertLessThanOrEqual(fraction, Self.allowedFraction, "\(c.name): \(differing) pixels differ (\(fraction * 100)%)")
        }
    }
}
