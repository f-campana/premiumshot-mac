import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
import PremiumShotCore
@testable import PremiumShotMac

enum Fixtures {
    static func url(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures").appendingPathComponent(name)
    }
    static func data(_ name: String) throws -> Data { try Data(contentsOf: url(name)) }
    static func source(_ name: String) throws -> SourceImage { try ImageLoader.load(url: url(name)) }

    /// The fixture re-encoded as TIFF, to stand in for a screenshot copied by an app that puts TIFF on the pasteboard.
    static func tiffData(_ name: String) throws -> Data {
        let image = try source(name).cgImage
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

/// A private, uniquely named pasteboard so tests never touch the real clipboard.
func makePasteboard() -> NSPasteboard {
    let pb = NSPasteboard(name: NSPasteboard.Name("com.fabien.premiumshot.test.\(UUID().uuidString)"))
    pb.clearContents()
    return pb
}

func makeDefaults() -> UserDefaults {
    let name = "com.fabien.premiumshot.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
