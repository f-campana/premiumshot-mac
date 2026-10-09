import Foundation

/// Bounds handling for the fixed presentation; there is no user position to persist.
public enum PanelPlacement {
    public static func clamp(_ frame: CGRect, to area: CGRect) -> CGRect {
        let usable = area.insetBy(dx: 12, dy: 12)
        return CGRect(
            x: min(max(frame.minX, usable.minX), max(usable.minX, usable.maxX - frame.width)),
            y: min(max(frame.minY, usable.minY), max(usable.minY, usable.maxY - frame.height)),
            width: frame.width, height: frame.height)
    }
}
