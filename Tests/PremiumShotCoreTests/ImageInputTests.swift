import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PremiumShotCore

final class ImageInputTests: XCTestCase {
    func testPNGAndHEICLoad() throws {
        let png = try Fixtures.source("small-dialog.png"), heic = try Fixtures.source("small-dialog.heic")
        XCTAssertEqual(png.width, heic.width); XCTAssertEqual(png.height, heic.height)
    }

    func testOrientationTagIsApplied() throws {
        let rotated = try Fixtures.source("rotated-dialog.jpg"), upright = try Fixtures.source("small-dialog.png")
        XCTAssertEqual(rotated.width, upright.height, "a 90° orientation tag swaps width and height")
        XCTAssertEqual(rotated.height, upright.width)
    }

    func testSourceColourSpaceIsPreserved() throws {
        XCTAssertEqual(try Fixtures.source("p3-patches.png").cgImage.colorSpace?.name as String?, CGColorSpace.displayP3 as String)
        XCTAssertEqual(try Fixtures.source("small-dialog.png").cgImage.colorSpace?.name as String?, CGColorSpace.sRGB as String)
    }

    func testTopLuminanceSeparatesDarkAndLightScreenshots() throws {
        XCTAssertLessThan(try Fixtures.source("wide-dashboard.png").topLuminance, 0.42)
        XCTAssertGreaterThan(try Fixtures.source("small-dialog.png").topLuminance, 0.42)
    }

    func testGIFIsRejectedWithAClearMessage() throws {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, try Fixtures.source("thin-strip.png").cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertThrowsError(try ImageLoader.load(data: data as Data)) { error in
            guard case PremiumShotError.unsupportedFormat = error else { return XCTFail("wrong error \(error)") }
            XCTAssertEqual((error as? PremiumShotError)?.exitCode, 3)
        }
    }

    func testNonImageDataIsRejected() {
        XCTAssertThrowsError(try ImageLoader.load(data: Data("hello".utf8))) { error in
            guard case PremiumShotError.unreadableImage = error else { return XCTFail("wrong error \(error)") }
        }
        XCTAssertThrowsError(try ImageLoader.load(url: URL(fileURLWithPath: "/nonexistent/file.png")))
    }

    /// 8200 × 8200 = 67.2 MP is over the 64 MP limit. A 1-bit image keeps the test cheap.
    func testImageOverTheMegapixelLimitIsRejected() throws {
        let side = 8200, bytesPerRow = (side + 7) / 8
        let provider = CGDataProvider(data: Data(count: bytesPerRow * side) as CFData)!
        let image = CGImage(width: side, height: side, bitsPerComponent: 1, bitsPerPixel: 1, bytesPerRow: bytesPerRow,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let data = try PNG.encode(image)
        XCTAssertThrowsError(try ImageLoader.load(data: data)) { error in
            guard case PremiumShotError.imageTooLarge(let pixels, let limit) = error else { return XCTFail("wrong error \(error)") }
            XCTAssertEqual(pixels, side * side); XCTAssertEqual(limit, 64_000_000)
            XCTAssertEqual((error as? PremiumShotError)?.exitCode, 4)
        }
    }

    func testPNGWriteFailureIsReportedNotThrownAsACrash() throws {
        let data = try PNG.encode(try Fixtures.source("thin-strip.png").cgImage)
        XCTAssertThrowsError(try PNG.write(data, to: URL(fileURLWithPath: "/nonexistent-directory/out.png"))) { error in
            guard case PremiumShotError.writeFailed = error else { return XCTFail("wrong error \(error)") }
            XCTAssertEqual((error as? PremiumShotError)?.exitCode, 5)
        }
    }
}
