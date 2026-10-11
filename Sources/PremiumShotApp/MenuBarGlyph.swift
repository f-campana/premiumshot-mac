import AppKit

enum MenuBarGlyph {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let outer = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3, width: 15, height: 12), xRadius: 3, yRadius: 3)
            outer.lineWidth = 1
            outer.stroke()
            let inner = NSBezierPath(roundedRect: NSRect(x: 4.5, y: 6, width: 9, height: 6), xRadius: 1.5, yRadius: 1.5)
            inner.lineWidth = 1
            inner.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "PremiumShot"
        return image
    }
}
