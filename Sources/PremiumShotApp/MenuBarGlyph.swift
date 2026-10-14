import AppKit

enum MenuBarGlyph {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let outer = NSBezierPath()
            outer.move(to: NSPoint(x: 10.5, y: 14.5))
            outer.line(to: NSPoint(x: 5, y: 14.5))
            outer.curve(to: NSPoint(x: 2.5, y: 12), controlPoint1: NSPoint(x: 3.5, y: 14.5), controlPoint2: NSPoint(x: 2.5, y: 13.5))
            outer.line(to: NSPoint(x: 2.5, y: 6))
            outer.curve(to: NSPoint(x: 5, y: 3.5), controlPoint1: NSPoint(x: 2.5, y: 4.5), controlPoint2: NSPoint(x: 3.5, y: 3.5))
            outer.line(to: NSPoint(x: 13, y: 3.5))
            outer.curve(to: NSPoint(x: 15.5, y: 6), controlPoint1: NSPoint(x: 14.5, y: 3.5), controlPoint2: NSPoint(x: 15.5, y: 4.5))
            outer.line(to: NSPoint(x: 15.5, y: 9.5))
            outer.lineWidth = 1
            outer.stroke()
            let corner = NSBezierPath()
            corner.move(to: NSPoint(x: 12.5, y: 15.5))
            corner.line(to: NSPoint(x: 16.5, y: 15.5))
            corner.line(to: NSPoint(x: 16.5, y: 11.5))
            corner.lineWidth = 1
            corner.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "PremiumShot"
        return image
    }
}
