import AppKit
import ImageIO
import UniformTypeIdentifiers

// Original installer artwork. Finder supplies the two draggable icons and labels.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 600, height: 400)
let artwork = NSImage(size: size, flipped: false) { _ in
    NSColor(srgbRed: 0.984, green: 0.977, blue: 0.971, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    let field = NSGradient(colors: [
        NSColor(srgbRed: 1, green: 0.92, blue: 0.88, alpha: 0.7),
        NSColor(srgbRed: 0.97, green: 0.91, blue: 0.98, alpha: 0)])!
    field.draw(fromCenter: NSPoint(x: 300, y: 105), radius: 0,
               toCenter: NSPoint(x: 300, y: 105), radius: 300, options: [])
    func text(_ value: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let line = NSAttributedString(string: value, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        line.draw(at: NSPoint(x: (600 - line.size().width) / 2, y: y))
    }
    let ink = NSColor(srgbRed: 0.16, green: 0.17, blue: 0.19, alpha: 1)
    let secondary = NSColor(srgbRed: 0.35, green: 0.35, blue: 0.38, alpha: 1)
    text("PremiumShot", y: 322, size: 30, weight: .semibold, color: ink)
    text("Screenshots, worth sharing.", y: 296, size: 14, weight: .regular, color: secondary)
    text("→", y: 169, size: 32, weight: .light, color: secondary)
    text("Drag PremiumShot to Applications.", y: 91, size: 13, weight: .medium, color: ink)
    NSColor(srgbRed: 0.85, green: 0.81, blue: 0.82, alpha: 1).setStroke()
    let divider = NSBezierPath(); divider.move(to: NSPoint(x: 48, y: 72)); divider.line(to: NSPoint(x: 552, y: 72))
    divider.lineWidth = 0.5; divider.stroke()
    text("If macOS blocks it: System Settings → Privacy & Security → Open Anyway", y: 47,
         size: 11, weight: .regular, color: secondary)
    text("Private beta · Apple Silicon · macOS 26", y: 27, size: 10, weight: .regular, color: secondary)
    return true
}
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.tiff.identifier as CFString, 2, nil)!
for scale in [1, 2] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600 * scale, pixelsHigh: 400 * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    artwork.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    let dpi = 72 * scale
    CGImageDestinationAddImage(destination, rep.cgImage!, [
        kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi,
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5,
            kCGImagePropertyTIFFResolutionUnit: 2, kCGImagePropertyTIFFXResolution: dpi,
            kCGImagePropertyTIFFYResolution: dpi],
    ] as CFDictionary)
}
precondition(CGImageDestinationFinalize(destination))
