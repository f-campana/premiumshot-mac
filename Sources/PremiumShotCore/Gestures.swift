import Foundation

public enum FingerDirection: Equatable, Sendable { case up, down }
public enum ZoomIntent: Equatable, Sendable { case zoomIn, zoomOut }

/// Direction math for the Inspect swipe. Pure, so it can be tested without a trackpad.
public enum Gestures {
    /// Which way the fingers moved, independent of the system "natural scrolling" setting.
    ///
    /// AppKit reports `scrollingDeltaY > 0` when content should move down (scrolling up). With natural scrolling
    /// (`directionInvertedFromDevice == true`) content follows the fingers, so fingers up means a negative delta.
    /// Without it, fingers up means a positive delta.
    public static func fingerDirection(scrollingDeltaY: Double, directionInvertedFromDevice inverted: Bool) -> FingerDirection? {
        guard scrollingDeltaY != 0 else { return nil }
        let fingersUp = inverted ? scrollingDeltaY < 0 : scrollingDeltaY > 0
        return fingersUp ? .up : .down
    }

    /// Spec: two-finger swipe up zooms in, down zooms out.
    public static func zoomIntent(scrollingDeltaY: Double, directionInvertedFromDevice inverted: Bool) -> ZoomIntent? {
        switch fingerDirection(scrollingDeltaY: scrollingDeltaY, directionInvertedFromDevice: inverted) {
        case .up: return .zoomIn
        case .down: return .zoomOut
        case nil: return nil
        }
    }
}
