import AppKit
import ImageIO
import UniformTypeIdentifiers

// Original vector artwork. Icon Composer supplies the platform mask and material.
let output = CommandLine.arguments[1]
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 255) / 255,
        CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, alpha])!
}
func canvas() -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func save(_ context: CGContext, _ name: String) {
    let url = URL(fileURLWithPath: output).appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
}
let field = canvas()
field.setFillColor(color(0xf2d6cb)); field.fill(CGRect(x: 0, y: 0, width: size, height: size))
for (x, y, radius, hex): (Double, Double, Double, UInt32) in [
    (0.10, 0.05, 0.85, 0xffb59e), (0.95, 0.10, 0.70, 0xdcc4ff),
    (0.85, 1.00, 0.90, 0xffd8a6), (0.00, 0.95, 0.70, 0xf7b6cc)
] {
    let centre = CGPoint(x: x * Double(size), y: (1 - y) * Double(size))
    let gradient = CGGradient(colorsSpace: space, colors: [color(hex), color(hex, 0)] as CFArray, locations: [0, 1])!
    field.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
        endCenter: centre, endRadius: radius * Double(size), options: [])
}
save(field, "Dawn.png")
let window = canvas()
let rect = CGRect(x: 188, y: 228, width: 648, height: 568)
let path = CGPath(roundedRect: rect, cornerWidth: 86, cornerHeight: 86, transform: nil)
window.setShadow(offset: CGSize(width: 0, height: -22), blur: 34, color: color(0x502b34, 0.28))
window.addPath(path); window.setFillColor(color(0x242933)); window.fillPath()
window.setShadow(offset: .zero, blur: 0)
window.saveGState(); window.addPath(path); window.clip()
let fill = CGGradient(colorsSpace: space, colors: [color(0x3c4250), color(0x1c2029)] as CFArray, locations: [0, 1])!
window.drawLinearGradient(fill, start: CGPoint(x: 280, y: 796), end: CGPoint(x: 720, y: 228),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
window.restoreGState()
window.addPath(path); window.setStrokeColor(color(0xffffff, 0.34)); window.setLineWidth(3); window.strokePath()
// The inset reads as a screenshot at small sizes. A single bright corner adds the finishing-touch cue.
let inner = CGPath(roundedRect: rect.insetBy(dx: 58, dy: 58), cornerWidth: 34, cornerHeight: 34, transform: nil)
window.addPath(inner); window.setStrokeColor(color(0xf2d6cb, 0.62)); window.setLineWidth(12); window.strokePath()
window.setLineCap(.round); window.setLineJoin(.round); window.setLineWidth(52)
window.setStrokeColor(color(0xfff8ef)); window.move(to: CGPoint(x: 738, y: 626))
window.addLine(to: CGPoint(x: 738, y: 730)); window.addLine(to: CGPoint(x: 634, y: 730)); window.strokePath()
save(window, "Screenshot.png")
