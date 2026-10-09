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

    /// Fuse the opaque Overlay blend into the background bitmap. This avoids a second full bitmap and
    /// Quartz's costly generic blend pass; screenshot pixels are drawn afterwards and never touched.
    static func apply(to context: CGContext, opacity: Double) throws {
        guard let data = context.data else { return }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let alpha = Int((opacity * 10000).rounded())
        // The blend has only 121 noise values and 256 channel values. Resolve its integer
        // divisions once instead of repeating them for every channel of every output pixel.
        var blend = [UInt8](repeating: 0, count: 121 * 256)
        for noise in 68...188 {
            for base in 0...255 {
                let overlay =
                    base < 128
                    ? (2 * base * noise + 127) / 255
                    : 255 - (2 * (255 - base) * (255 - noise) + 127) / 255
                blend[(noise - 68) * 256 + base] = UInt8(
                    clamping: (base * (10000 - alpha) + overlay * alpha + 5000) / 10000)
            }
        }
        try blend.withUnsafeBufferPointer { table in
            for y in 0..<context.height {
                if y % 32 == 0 { try Task.checkCancellation() }
                let row = y * context.bytesPerRow
                for x in 0..<context.width {
                    let noiseIndex = (Int(hash(UInt32(x), UInt32(y)) & 0xffff) * 120 / 65535) * 256
                    let index = row + x * 4
                    pixels[index] = table[noiseIndex + Int(pixels[index])]
                    pixels[index + 1] = table[noiseIndex + Int(pixels[index + 1])]
                    pixels[index + 2] = table[noiseIndex + Int(pixels[index + 2])]
                }
            }
        }
    }

    /// Mid-grey noise, value = 128 + (u − 0.5) × 120, as an opaque RGBA image tagged with `space`.
    static func image(width: Int, height: Int, space: CGColorSpace) -> CGImage? {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * height)
        pixels.withUnsafeMutableBufferPointer { buffer in
            for y in 0..<height {
                let row = y * bytesPerRow
                for x in 0..<width {
                    let u =
                        Double(hash(UInt32(truncatingIfNeeded: x), UInt32(truncatingIfNeeded: y)) & 0xFFFF)
                        / 65535
                    let v = UInt8(clamping: Int(128 + ((u - 0.5) * 120).rounded(.towardZero)))
                    let i = row + x * 4
                    buffer[i] = v
                    buffer[i + 1] = v
                    buffer[i + 2] = v
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
