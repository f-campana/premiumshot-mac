import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A decoded screenshot, with orientation applied and its own colour space preserved.
public final class SourceImage: @unchecked Sendable {  // immutable after init; CGImage is read-only
    public let cgImage: CGImage
    public var width: Int { cgImage.width }
    public var height: Int { cgImage.height }
    public init(cgImage: CGImage) { self.cgImage = cgImage }

}

public enum ImageLoader {
    /// Hard limit from the spec: 64 megapixels.
    public static let maxPixels = 64_000_000

    /// Accepted formats. Everything else (GIF, RAW, PDF, animated images) is rejected with a clear message.
    static let accepted: [UTType] = [.png, .jpeg, .heic, .heif, .tiff]

    public static func supports(_ type: UTType) -> Bool {
        accepted.contains { type.conforms(to: $0) }
    }

    public static func load(url: URL) throws -> SourceImage {
        guard url.isFileURL else {
            throw PremiumShotError.unreadableImage("Choose a local image file.")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw PremiumShotError.unreadableImage("The file could not be opened.")
        }
        return try load(source: source)
    }

    public static func load(data: Data) throws -> SourceImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw PremiumShotError.unreadableImage("The data is not an image.")
        }
        return try load(source: source)
    }

    static func load(source: CGImageSource) throws -> SourceImage {
        guard let typeID = CGImageSourceGetType(source), let type = UTType(typeID as String) else {
            throw PremiumShotError.unreadableImage("The data is not a recognised image.")
        }
        guard supports(type) else {
            throw PremiumShotError.unsupportedFormat(
                "\(type.localizedDescription ?? type.identifier) is not supported. Use PNG, JPEG, HEIC or TIFF."
            )
        }
        guard CGImageSourceGetCount(source) > 0,
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, w > 0, h > 0
        else {
            throw PremiumShotError.unreadableImage("The image has no readable pixels.")
        }
        let pixels = w * h
        guard pixels <= maxPixels else {
            throw PremiumShotError.imageTooLarge(pixels: pixels, limit: maxPixels)
        }

        // Frame 0 only. The thumbnail API at full size applies the orientation tag and keeps the colour space.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PremiumShotError.unreadableImage("The image could not be decoded.")
        }
        return SourceImage(cgImage: image)
    }
}
