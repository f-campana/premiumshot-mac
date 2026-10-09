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

/// File URLs express intent. Their accompanying TIFF often represents a Finder icon,
/// so image bytes are captured only for payloads without files.
struct ImageImportPayload: Sendable {
    let files: [URL]
    let images: [Data]
    var isEmpty: Bool { files.isEmpty && images.isEmpty }

    init(_ board: NSPasteboard) {
        files = Self.fileURLs(board)
        images = files.isEmpty ? PasteboardIO.imageDataTypes.compactMap { board.data(forType: $0) } : []
    }

    static func fileURLs(_ board: NSPasteboard) -> [URL] {
        (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    static func plausibleImageFile(_ url: URL) -> Bool {
        guard url.isFileURL,
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey]),
            values.isDirectory == false,
            let type = values.contentType ?? UTType(filenameExtension: url.pathExtension)
        else { return false }
        return ImageLoader.supports(type)
    }

    func decode() throws -> SourceImage {
        var last: Error = PremiumShotError.unreadableImage("The clipboard has no image.")
        for url in files {
            do { return try ImageLoader.load(url: url) } catch { last = error }
        }
        for data in images {
            do { return try ImageLoader.load(data: data) } catch { last = error }
        }
        throw last
    }
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
    public static let dropTypes: [NSPasteboard.PasteboardType] = [.fileURL] + imageDataTypes

    public static func marker(on pasteboard: NSPasteboard) -> UUID? {
        pasteboard.string(forType: sessionMarkerType).flatMap(UUID.init(uuidString:))
    }

    /// Reads the best image from `pasteboard`.
    ///
    /// Image files copied in Finder are checked first: Finder may also place the file's *icon* on the pasteboard
    /// as image data, and the file itself is what was meant.
    public static func read(from pasteboard: NSPasteboard = .general) -> ClipboardContent {
        let marker = marker(on: pasteboard)
        let payload = ImageImportPayload(pasteboard)
        guard !payload.isEmpty else { return .none(reason: nil) }
        do { return .image(try payload.decode(), marker: marker) }
        catch { return .none(reason: error.localizedDescription) }
    }

    /// Replaces the pasteboard contents with a PNG and the session marker. Returns true only if the write was
    /// accepted **and** the data reads back with the expected pixel size, so callers can confirm after delivery.
    @discardableResult
    public static func writePNG(
        _ data: Data, marker: UUID, expectedSize: (width: Int, height: Int),
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        item.setString(marker.uuidString, forType: sessionMarkerType)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { return false }
        guard let readBack = pasteboard.data(forType: .png), let size = PNG.dimensions(readBack) else {
            return false
        }
        return size.width == expectedSize.width && size.height == expectedSize.height
            && Self.marker(on: pasteboard) == marker
    }
}
