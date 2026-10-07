import AppKit
import PremiumShotCore
import UniformTypeIdentifiers

/// What a summon found on a pasteboard.
public enum ClipboardContent {
    /// An image, plus the source-session marker if the image is our own earlier output.
    case image(SourceImage, marker: UUID?)
    /// Nothing usable. `reason` is a one-line explanation when data was present but unreadable.
    case none(reason: String?)
}

public enum PasteboardIO {
    /// Private pasteboard type carrying the UUID of the in-memory source session that produced a Copy.
    public static let sessionMarkerType = NSPasteboard.PasteboardType("com.fabien.premiumshot.session")

    static let imageDataTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff,
        NSPasteboard.PasteboardType(UTType.jpeg.identifier),
        NSPasteboard.PasteboardType(UTType.heic.identifier),
        NSPasteboard.PasteboardType(UTType.heif.identifier),
    ]

    public static func marker(on pasteboard: NSPasteboard) -> UUID? {
        pasteboard.string(forType: sessionMarkerType).flatMap(UUID.init(uuidString:))
    }

    /// Reads the best image from `pasteboard`.
    ///
    /// Image files copied in Finder are checked first: Finder may also place the file's *icon* on the pasteboard
    /// as image data, and the file itself is what was meant.
    public static func read(from pasteboard: NSPasteboard = .general) -> ClipboardContent {
        let marker = marker(on: pasteboard)
        var reason: String?

        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        for url in urls {
            do { return .image(try ImageLoader.load(url: url), marker: marker) }
            catch { reason = error.localizedDescription }
        }
        for type in imageDataTypes {
            guard let data = pasteboard.data(forType: type) else { continue }
            do { return .image(try ImageLoader.load(data: data), marker: marker) }
            catch { reason = error.localizedDescription }
        }
        return .none(reason: reason)
    }

    /// Replaces the pasteboard contents with a PNG and the session marker. Returns true only if the write was
    /// accepted **and** the data reads back with the expected pixel size, so callers can confirm after delivery.
    @discardableResult
    public static func writePNG(_ data: Data, marker: UUID, expectedSize: (width: Int, height: Int), to pasteboard: NSPasteboard = .general) -> Bool {
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        item.setString(marker.uuidString, forType: sessionMarkerType)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { return false }
        guard let readBack = pasteboard.data(forType: .png), let decoded = PNG.inspect(readBack) else { return false }
        return decoded.image.width == expectedSize.width && decoded.image.height == expectedSize.height
            && Self.marker(on: pasteboard) == marker
    }
}
