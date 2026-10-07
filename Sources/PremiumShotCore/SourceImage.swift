import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A decoded screenshot, with orientation applied and its own colour space preserved.
public final class SourceImage: @unchecked Sendable {   // immutable after init; CGImage is read-only
    public let cgImage: CGImage
    public var width: Int { cgImage.width }
    public var height: Int { cgImage.height }
    /// Mean luminance (0...1) of the top strip. Decides whether the Window and Browser frames use dark chrome.
    public let topLuminance: Double

    public init(cgImage: CGImage) {
        self.cgImage = cgImage
        self.topLuminance = SourceImage.measureTopLuminance(cgImage)
    }

    private static func measureTopLuminance(_ image: CGImage) -> Double {
        let w = min(image.width, 600), h = min(image.height, 10)
        guard w > 0, h > 0, let crop = image.cropping(to: CGRect(x: 0, y: 0, width: w, height: h)),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = ctx.data else { return 0.5 }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        let p = data.assumingMemoryBound(to: UInt8.self)
        var sum = 0.0
        for i in 0..<(w * h) {
            sum += 0.2126 * Double(p[i * 4]) + 0.7152 * Double(p[i * 4 + 1]) + 0.0722 * Double(p[i * 4 + 2])
        }
        return sum / Double(w * h) / 255
    }
}

public enum ImageLoader {
    /// Hard limit from the spec: 64 megapixels.
    public static let maxPixels = 64_000_000

    /// Accepted formats. Everything else (GIF, RAW, PDF, animated images) is rejected with a clear message.
    static let accepted: [UTType] = [.png, .jpeg, .heic, .heif, .tiff]

    public static func load(url: URL) throws -> SourceImage {
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
        guard accepted.contains(where: { type.conforms(to: $0) }) else {
            throw PremiumShotError.unsupportedFormat("\(type.localizedDescription ?? type.identifier) is not supported. Use PNG, JPEG, HEIC or TIFF.")
        }
        guard CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, w > 0, h > 0 else {
            throw PremiumShotError.unreadableImage("The image has no readable pixels.")
        }
        let pixels = w * h
        guard pixels <= maxPixels else { throw PremiumShotError.imageTooLarge(pixels: pixels, limit: maxPixels) }

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
