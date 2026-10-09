import Foundation
import PremiumShotCore

/// A bounded spring along the path between layouts; retargeting projects the current velocity onto the new path.
struct CompositionMotion {
    private var start: PresentationGeometry
    private var target: PresentationGeometry
    private var position = 0.0
    private var velocity = 0.0
    var geometry: PresentationGeometry { start.interpolated(to: target, fraction: position) }
    var finished: Bool { abs(1 - position) < 0.002 && abs(velocity) < 0.02 }
    init(from: PresentationGeometry, to: PresentationGeometry) {
        start = from
        target = to
    }
    mutating func retarget(_ next: PresentationGeometry) {
        let current = geometry
        let previousDirection = zip(start.values, target.values).map { $1 - $0 }
        let nextDirection = zip(current.values, next.values).map { $1 - $0 }
        let length = nextDirection.reduce(0) { $0 + $1 * $1 }
        let projection = zip(previousDirection, nextDirection).reduce(0) { $0 + $1.0 * $1.1 }
        velocity = length > 1e-12 ? max(0, velocity * projection / length) : 0
        start = current
        target = next
        position = 0
    }
    mutating func advance(seconds: Double) {
        var remaining = min(0.05, max(0, seconds))
        let damping = 2 * 0.88 * sqrt(340.0)
        while remaining > 0 {
            let dt = min(0.004, remaining)
            velocity += (340 * (1 - position) - damping * velocity) * dt
            position = min(1, max(0, position + velocity * dt))
            if position == 1 { velocity = 0 }
            remaining -= dt
        }
    }
}
