import CoreGraphics
import Foundation
import ImageIO
@testable import PremiumShotCore

enum Fixtures {
    /// fixtures/ at the package root, found relative to this file so tests run from any directory.
    static func url(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures").appendingPathComponent(name)
    }
    static func source(_ name: String) throws -> SourceImage { try ImageLoader.load(url: url(name)) }
}

/// Raw premultiplied RGBA bytes of `image` drawn 1:1 into a context of `space`, with no resampling.
/// Drawing into the image's own colour space is an identity, so this reads pixels exactly.
func pixels(of image: CGImage, in space: CGColorSpace? = nil) -> [UInt8] {
    let space = space ?? image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    ctx.interpolationQuality = .none
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: w * h * 4))
}

/// RGBA of one pixel, with y measured from the top.
func pixel(_ bytes: [UInt8], width: Int, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    let i = (y * width + x) * 4
    return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
}
