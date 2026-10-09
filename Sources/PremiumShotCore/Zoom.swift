import Foundation

/// Inspect geometry uses backing pixels: 100% is one export pixel per backing pixel.
public struct Zoom: Equatable, Sendable {
    public var scale: Double = 1
    public var x: Double = 0, y: Double = 0
    public var floor: Double = 1
    public var fitScale: Double = 1
    public var imageWidth: Double = 1, imageHeight: Double = 1
    public var viewportWidth: Double = 1, viewportHeight: Double = 1
    public init() {}
    public mutating func configure(
        width: Double, height: Double, viewportWidth: Double, viewportHeight: Double, backingScale: Double,
        fit: Bool
    ) {
        imageWidth = max(1, width) / max(1, backingScale)
        imageHeight = max(1, height) / max(1, backingScale)
        self.viewportWidth = max(1, viewportWidth)
        self.viewportHeight = max(1, viewportHeight)
        fitScale = min(4, min(self.viewportWidth / imageWidth, self.viewportHeight / imageHeight))
        floor = min(1, fitScale)
        if fit {
            scale = fitScale
            x = 0
            y = 0
        } else {
            scale = min(4, max(floor, scale))
            clampPan()
        }
    }
    public mutating func zoom(to value: Double, anchorX: Double = 0, anchorY: Double = 0) {
        let next = min(4, max(floor, value))
        let ratio = next / scale
        x = anchorX - (anchorX - x) * ratio
        y = anchorY - (anchorY - y) * ratio
        scale = next
        clampPan()
    }
    public mutating func pan(dx: Double, dy: Double) {
        x += dx
        y += dy
        clampPan()
    }
    private mutating func clampPan() {
        let maxX = max(0, (imageWidth * scale - viewportWidth) / 2)
        let maxY = max(0, (imageHeight * scale - viewportHeight) / 2)
        x = min(maxX, max(-maxX, x))
        y = min(maxY, max(-maxY, y))
    }
}
