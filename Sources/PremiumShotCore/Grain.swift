import CoreGraphics
import Foundation

/// Deterministic film grain. It keeps smooth gradients from banding.
///
/// The field is a pure function of **output pixel coordinates** and a fixed seed, so the same output size
/// always gets the same grain, and a downsampled export and a preview agree. (The mock used random noise
/// tiled at each resolution, which cannot be reproduced.)
enum Grain {
    static let seed: UInt32 = 0x5EED_0001
    /// Overlay opacity, from the mock.
    static let opacity: CGFloat = 0.13

    @inline(__always) static func hash(_ x: UInt32, _ y: UInt32) -> UInt32 {
        var h = x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 2_246_822_519
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        h = (h ^ (h >> 15)) &* 2_654_435_761
        return h ^ (h >> 13)
    }

    /// Mid-grey noise, value = 128 + (u − 0.5) × 120, as an opaque RGBA image tagged with `space`.
    static func image(width: Int, height: Int, space: CGColorSpace) -> CGImage? {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * height)
        pixels.withUnsafeMutableBufferPointer { buffer in
            for y in 0..<height {
                let row = y * bytesPerRow
                for x in 0..<width {
                    let u = Double(hash(UInt32(truncatingIfNeeded: x), UInt32(truncatingIfNeeded: y)) & 0xFFFF) / 65535
                    let v = UInt8(clamping: Int(128 + ((u - 0.5) * 120).rounded(.towardZero)))
                    let i = row + x * 4
                    buffer[i] = v; buffer[i + 1] = v; buffer[i + 2] = v
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
