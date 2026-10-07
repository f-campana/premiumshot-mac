import AppKit
import UniformTypeIdentifiers
import XCTest
import PremiumShotCore
@testable import PremiumShotMac

/// Spike S6 (clipboard read) and the pasteboard half of R2 / I2 / I6, against private pasteboards.
@MainActor
final class PasteboardTests: XCTestCase {
    func imageSize(_ content: ClipboardContent) -> (Int, Int)? {
        if case .image(let image, _) = content { return (image.width, image.height) }
        return nil
    }

    func testReadsEveryImageDataTypeWeSupport() throws {
        let expected = (880, 624)
        let cases: [(String, NSPasteboard.PasteboardType, Data)] = [
            ("PNG", .png, try Fixtures.data("small-dialog.png")),
            ("TIFF", .tiff, try Fixtures.tiffData("small-dialog.png")),
            ("HEIC", NSPasteboard.PasteboardType(UTType.heic.identifier), try Fixtures.data("small-dialog.heic")),
        ]
        for (name, type, data) in cases {
            let pb = makePasteboard(); defer { pb.releaseGlobally() }
            pb.setData(data, forType: type)
            let size = imageSize(PasteboardIO.read(from: pb))
            XCTAssertEqual(size?.0, expected.0, name); XCTAssertEqual(size?.1, expected.1, name)
        }
        // JPEG (the fixture carries an orientation tag, so its upright size is swapped).
        let pb = makePasteboard(); defer { pb.releaseGlobally() }
        pb.setData(try Fixtures.data("rotated-dialog.jpg"), forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier))
        XCTAssertEqual(imageSize(PasteboardIO.read(from: pb))?.0, 624)
    }

    func testReadsAnImageFileCopiedInFinder() throws {
        let pb = makePasteboard(); defer { pb.releaseGlobally() }
        XCTAssertTrue(pb.writeObjects([Fixtures.url("wide-dashboard.png") as NSURL]))
        let size = imageSize(PasteboardIO.read(from: pb))
        XCTAssertEqual(size?.0, 2560); XCTAssertEqual(size?.1, 1040)
    }

    /// Finder can put the file's icon on the pasteboard as image data too. The file is what was meant.
    func testFileWinsOverAnAccompanyingIcon() throws {
        let pb = makePasteboard(); defer { pb.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString(Fixtures.url("wide-dashboard.png").absoluteString, forType: .fileURL)
        item.setData(try Fixtures.tiffData("thin-strip.png"), forType: .tiff)   // stands in for the icon
        XCTAssertTrue(pb.writeObjects([item]))
        XCTAssertEqual(imageSize(PasteboardIO.read(from: pb))?.0, 2560)
    }

    func testEmptyAndUnreadableContentIsRecoverable() throws {
        let empty = makePasteboard(); defer { empty.releaseGlobally() }
        guard case .none(let reason) = PasteboardIO.read(from: empty) else { return XCTFail("empty pasteboard should give .none") }
        XCTAssertNil(reason)

        let junk = makePasteboard(); defer { junk.releaseGlobally() }
        junk.setData(Data("not an image".utf8), forType: .png)
        guard case .none(let junkReason) = PasteboardIO.read(from: junk) else { return XCTFail("junk should give .none") }
        XCTAssertNotNil(junkReason, "unreadable data comes with a reason")

        let text = makePasteboard(); defer { text.releaseGlobally() }
        text.setString("just text", forType: .string)
        guard case .none = PasteboardIO.read(from: text) else { return XCTFail("text is not an image") }

        let gif = makePasteboard(); defer { gif.releaseGlobally() }
        XCTAssertTrue(gif.writeObjects([Fixtures.url("exact-pattern.png").deletingLastPathComponent().appendingPathComponent("nothing.png") as NSURL]))
        guard case .none = PasteboardIO.read(from: gif) else { return XCTFail("a missing file is not an image") }
    }

    // R2 (clipboard half) and the "after delivery" rule behind I2.
    func testWritePNGReadsBackAtTheResolvedSizeWithTheMarker() throws {
        let pb = makePasteboard(); defer { pb.releaseGlobally() }
        let result = try Renderer.render(source: try Fixtures.source("small-dialog.png"), recipe: .default)
        let marker = UUID()
        XCTAssertTrue(PasteboardIO.writePNG(try PNG.encode(result.image), marker: marker, expectedSize: (result.layout.width, result.layout.height), to: pb))
        XCTAssertEqual(PasteboardIO.marker(on: pb), marker)
        let decoded = PNG.inspect(try XCTUnwrap(pb.data(forType: .png)))
        XCTAssertEqual(decoded?.image.width, result.layout.width); XCTAssertEqual(decoded?.image.height, result.layout.height)
        XCTAssertEqual(decoded?.colorSpaceName, CGColorSpace.sRGB as String, "clipboard image is tagged")
    }

    func testWritePNGReportsFailureWhenTheSizeDoesNotMatch() throws {
        let pb = makePasteboard(); defer { pb.releaseGlobally() }
        let result = try Renderer.render(source: try Fixtures.source("thin-strip.png"), recipe: .default)
        XCTAssertFalse(PasteboardIO.writePNG(try PNG.encode(result.image), marker: UUID(), expectedSize: (1, 1), to: pb))
    }

    func testOwnOutputOnTheClipboardIsRecognised() throws {
        let pb = makePasteboard(); defer { pb.releaseGlobally() }
        let result = try Renderer.render(source: try Fixtures.source("thin-strip.png"), recipe: .default)
        let marker = UUID()
        PasteboardIO.writePNG(try PNG.encode(result.image), marker: marker, expectedSize: (result.layout.width, result.layout.height), to: pb)
        guard case .image(_, let found) = PasteboardIO.read(from: pb) else { return XCTFail("our own PNG should still read as an image") }
        XCTAssertEqual(found, marker)
    }
}
