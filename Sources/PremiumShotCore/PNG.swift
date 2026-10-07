import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PNG {
    /// Encodes `image` as PNG. ImageIO tags the file with the image's own colour space (an sRGB chunk or an
    /// embedded ICC profile), so the output is never untagged.
    public static func encode(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw PremiumShotError.encodeFailed("No PNG encoder is available.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PremiumShotError.encodeFailed("The encoder reported a failure.")
        }
        return data as Data
    }

    /// Writes PNG data to `url`, mapping filesystem failures to `.writeFailed`.
    public static func write(_ data: Data, to url: URL) throws {
        do { try data.write(to: url, options: .atomic) }
        catch { throw PremiumShotError.writeFailed(error.localizedDescription) }
    }

    /// Decodes PNG data and returns its image and the colour space name, for tests and verification.
    public static func inspect(_ data: Data) -> (image: CGImage, colorSpaceName: String?)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return (image, image.colorSpace?.name as String?)
    }
}
