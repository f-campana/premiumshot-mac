import AppKit
import Observation

enum PanelMode { case compact, adjust, inspect }

/// Geometry and fades share this pose; layout never uses its intermediate dimensions.
struct PanelPose {
    var card: CGRect
    var image: CGRect
    var compact = 1.0, drawer = 0.0, inspect = 0.0
    var values: [Double] {
        [
            card.minX, card.minY, card.width, card.height,
            image.minX, image.minY, image.width, image.height, compact, drawer, inspect,
        ]
    }
    init(card: CGRect, image: CGRect = .zero, compact: Double = 1, drawer: Double = 0, inspect: Double = 0) {
        self.card = card
        self.image = image
        self.compact = compact
        self.drawer = drawer
        self.inspect = inspect
    }
    init(values: [Double]) {
        card = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        image = CGRect(x: values[4], y: values[5], width: values[6], height: values[7])
        compact = values[8]
        drawer = values[9]
        inspect = values[10]
    }
}

/// Analytic critical damping stays time-based across missed display callbacks.
/// Reversal retains signed velocity: a moving edge decelerates before returning.
struct PanelTimeline {
    private(set) var start: PanelPose
    private(set) var target: PanelPose
    private(set) var duration: Double
    private var speed = 0.0
    private var tangent = Array(repeating: 0.0, count: 11)
    private var omega: Double { max(8 / duration, speed) }
    init(from: PanelPose, to: PanelPose, duration: Double) {
        start = from
        target = to
        self.duration = duration
    }
    func progress(at seconds: Double) -> (value: Double, velocity: Double) {
        if seconds >= duration { return (1, 0) }
        let t = max(0, seconds)
        let w = omega
        let decay = exp(-w * t)
        return (
            1 - (1 + (w - speed) * t) * decay,
            (speed + w * (w - speed) * t) * decay
        )
    }
    func pose(at seconds: Double) -> PanelPose {
        if seconds >= duration { return target }
        let t = max(0, seconds)
        let p = progress(at: seconds).value
        let carry = t * exp(-omega * t)
        return PanelPose(values: zip(zip(start.values, target.values), tangent).map {
            $0.0 + ($0.1 - $0.0) * p + $1 * carry
        })
    }
    func velocity(at seconds: Double) -> [Double] {
        if seconds >= duration { return Array(repeating: 0, count: 11) }
        let t = max(0, seconds)
        let v = progress(at: seconds).velocity
        let carry = (1 - omega * t) * exp(-omega * t)
        return zip(zip(start.values, target.values), tangent).map {
            ($0.1 - $0.0) * v + $1 * carry
        }
    }
    mutating func retarget(_ next: PanelPose, duration: Double, at seconds: Double, visible: PanelPose? = nil)
    {
        let current = visible ?? pose(at: seconds)
        let velocity = velocity(at: seconds)
        let direction = zip(current.values, next.values).map { $1 - $0 }
        let squared = direction.reduce(0) { $0 + $1 * $1 }
        speed =
            squared > 1e-12
            ? zip(velocity, direction).reduce(0) { $0 + $1.0 * $1.1 } / squared : 0
        // A new target need not lie on the old path (Adjust can become Inspect).
        // Keep the perpendicular velocity too, on the same damping timeline.
        tangent = zip(velocity, direction).map { $0 - $1 * speed }
        start = current
        target = next
        self.duration = duration
    }
}

/// The window's display link is the only clock for editor/Inspect transitions.
@MainActor final class PanelAnimator: NSObject {
    private weak var window: NSWindow?
    let state: PanelPresentation
    private let render: (PanelPose) -> Void
    private let reducesMotion: () -> Bool
    private var link: CADisplayLink?
    private var timeline: PanelTimeline?
    private var began = 0.0
    private(set) var pose: PanelPose
    init(
        window: NSWindow, state: PanelPresentation,
        reducesMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
        render: @escaping (PanelPose) -> Void
    ) {
        self.window = window
        self.state = state
        self.render = render
        self.reducesMotion = reducesMotion
        pose = PanelPose(card: window.frame)
    }
    func reset(_ pose: PanelPose, mode: PanelMode) {
        cancel()
        self.pose = pose
        state.settle(mode)
        render(pose)
    }
    func begin(_ target: PanelPose, mode: PanelMode, duration: Double, sharedImage: Bool) {
        let now = CACurrentMediaTime()
        if var running = timeline {
            running.retarget(target, duration: duration, at: now - began, visible: pose)
            timeline = running
        } else {
            timeline = PanelTimeline(from: pose, to: target, duration: duration)
        }
        began = now
        state.mode = mode
        state.showDrawer = mode == .adjust || pose.drawer > 0
        state.showInspect = mode == .inspect || pose.inspect > 0
        state.sharedImage = sharedImage
        state.active = true
        if reducesMotion() {
            snap()
            return
        }
        if link == nil, let window {
            let display = window.displayLink(target: self, selector: #selector(step(_:)))
            display.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            display.add(to: .main, forMode: .common)
            link = display
        }
        render(pose)
    }
    @objc private func step(_ display: CADisplayLink) {
        if reducesMotion() {
            snap()
            return
        }
        guard let timeline else {
            cancel()
            return
        }
        let elapsed = max(0, CACurrentMediaTime() - began)
        if elapsed >= timeline.duration {
            snap()
            return
        }
        pose = timeline.pose(at: elapsed)
        let p = min(1, max(0, timeline.progress(at: elapsed).value))
        func smooth(_ value: Double) -> Double {
            let v = min(1, max(0, value))
            return v * v * (3 - 2 * v)
        }
        let from = timeline.start
        let to = timeline.target
        let drawerRamp = to.drawer > from.drawer ? smooth((p - 0.4) / 0.6) : smooth(p / 0.6)
        let compactRamp = to.compact < from.compact ? smooth(p / 0.35) : smooth((p - 0.65) / 0.35)
        let inspectRamp = to.inspect > from.inspect ? smooth((p - 0.55) / 0.45) : smooth(p / 0.45)
        pose.drawer = from.drawer + (to.drawer - from.drawer) * drawerRamp
        pose.compact = from.compact + (to.compact - from.compact) * compactRamp
        pose.inspect = from.inspect + (to.inspect - from.inspect) * inspectRamp
        state.drawerOpacity = pose.drawer
        state.compactOpacity = pose.compact
        state.inspectOpacity = pose.inspect
        render(pose)
    }
    func snap() {
        guard let timeline else { return }
        pose = timeline.target
        cancel()
        state.settle(state.mode)
        render(pose)
    }
    func cancel() {
        link?.invalidate()
        link = nil
        timeline = nil
        state.active = false
    }
}

@MainActor @Observable final class PanelPresentation {
    var mode: PanelMode = .compact
    var inspectSize = CGSize(width: 960, height: 608)
    var compactOpacity = 1.0
    var drawerOpacity = 0.0
    var inspectOpacity = 0.0
    var sharedImage = false
    var active = false
    var showDrawer = false
    var showInspect = false
    func settle(_ mode: PanelMode) {
        self.mode = mode
        compactOpacity = mode == .inspect ? 0 : 1
        drawerOpacity = mode == .adjust ? 1 : 0
        inspectOpacity = mode == .inspect ? 1 : 0
        showDrawer = mode == .adjust
        showInspect = mode == .inspect
        sharedImage = false
        active = false
    }
}

/// A single bitmap travels between the two fixed layouts. It never handles input.
@MainActor final class SharedPreviewView: NSView {
    let imageLayer = CALayer()
    var showsTransparency = false
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        layer?.addSublayer(imageLayer)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    func place(image: CGImage?, rect: CGRect, opacity: Float = 1) {
        layer?.removeAnimation(forKey: "handoff")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        imageLayer.frame = rect
        imageLayer.opacity = 1
        layer?.opacity = opacity
        CATransaction.commit()
        needsDisplay = true
    }
    func revealUnderlyingImage(at rect: CGRect) {
        guard imageLayer.contents != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = rect
        layer?.opacity = 0
        CATransaction.commit()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.1
        layer?.add(fade, forKey: "handoff")
    }
    override func draw(_ dirtyRect: NSRect) {
        guard showsTransparency, imageLayer.contents != nil else { return }
        let rect = imageLayer.frame
        NSColor.controlBackgroundColor.setFill()
        rect.fill()
        NSColor.labelColor.withAlphaComponent(0.07).setFill()
        for y in stride(from: rect.minY, to: rect.maxY, by: 12) {
            for x in stride(from: rect.minX, to: rect.maxX, by: 12)
            where (Int((x - rect.minX) / 12) + Int((y - rect.minY) / 12)) % 2 == 0 {
                NSRect(x: x, y: y, width: min(12, rect.maxX - x), height: min(12, rect.maxY - y)).fill()
            }
        }
    }
}
