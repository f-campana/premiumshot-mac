import AppKit
import PremiumShotCore
import SwiftUI

struct HueStrip: NSViewRepresentable {
    let model: PanelModel
    func makeNSView(context: Context) -> HueStripView { HueStripView(model: model) }
    func updateNSView(_ view: HueStripView, context: Context) {
        view.update(enabled: context.environment.isEnabled)
        model.onKeyLoopChange?()
    }
}

final class HueStripView: NSView {
    let model: PanelModel
    let start: HueThumb, end: HueThumb
    private var lastPresentation: UInt64 = 0
    private var animation: Task<Void, Never>?
    private var animationTarget: GradientHues?
    private var burst: Task<Void, Never>?
    private var keyboardEditing = false
    private var top: HueThumb
    init(model: PanelModel) {
        self.model = model
        start = HueThumb(model: model, isStart: true)
        end = HueThumb(model: model, isStart: false)
        top = end
        super.init(frame: NSRect(x: 0, y: 0, width: 168, height: 32))
        addSubview(start)
        addSubview(end)
        start.strip = self
        end.strip = self
    }
    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { false }
    override func layout() {
        super.layout()
        position()
    }
    func update(enabled: Bool) {
        start.enabled = enabled
        end.enabled = enabled
        start.hue = model.recipe.gradientFrom
        end.hue = model.recipe.gradientTo
        let target = GradientHues(from: start.hue, to: end.hue)
        let newPresentation = lastPresentation != model.gradientPresentation
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        lastPresentation = model.gradientPresentation
        if newPresentation && model.gradientPresentationActive && enabled && !reduced {
            animateHandles(toward: target)
        } else if animation != nil
            && (animationTarget != target || !model.gradientPresentationActive || reduced || !enabled)
        {
            stopHandleAnimation()
        }
        if animation == nil {
            start.positionHue = Double(start.hue)
            end.positionHue = Double(end.hue)
            position()
        }
        needsDisplay = true
        start.needsDisplay = true
        end.needsDisplay = true
    }
    private func position() {
        for thumb in [start, end] {
            thumb.frame = NSRect(
                x: (bounds.width - 28) * thumb.positionHue / 360, y: bounds.midY - 14, width: 28, height: 28)
        }
    }
    private func stopHandleAnimation() {
        animation?.cancel()
        animation = nil
        animationTarget = nil
        start.positionHue = Double(start.hue)
        end.positionHue = Double(end.hue)
        position()
    }
    private func animateHandles(toward target: GradientHues) {
        animation?.cancel()
        animationTarget = target
        let a = start.positionHue
        let b = end.positionHue
        let targetA = Double(target.from)
        let targetB = Double(target.to)
        let revision = model.gradientPresentation
        animation = Task { [weak self] in
            let clock = ContinuousClock()
            let began = clock.now
            while let self, !Task.isCancelled, self.model.gradientPresentation == revision,
                self.model.gradientPresentationActive, self.animationTarget == target
            {
                let t = min(1, Timing.milliseconds(began.duration(to: clock.now)) / 250)
                let eased = t == 1 ? 1 : 1 - exp(-8 * t) * (cos(10 * t) + 0.8 * sin(10 * t))
                self.start.positionHue = min(360, max(0, a + (targetA - a) * eased))
                self.end.positionHue = min(360, max(0, b + (targetB - b) * eased))
                self.position()
                if t == 1 {
                    self.animation = nil
                    self.animationTarget = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard let self, !Task.isCancelled, self.model.gradientPresentation == revision,
                self.animationTarget == target
            else { return }
            self.stopHandleAnimation()
        }
    }
    func bringForward(_ thumb: HueThumb) {
        top = thumb
        addSubview(thumb, positioned: .above, relativeTo: thumb === start ? end : start)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if hypot(start.frame.midX - end.frame.midX, start.frame.midY - end.frame.midY) < 18,
            start.frame.union(end.frame).insetBy(dx: -2, dy: -2).contains(local)
        {
            return top
        }
        return super.hitTest(point)
    }
    func beginPointer(_ thumb: HueThumb) {
        stopHandleAnimation()
        endKeyboardBurst()
        bringForward(thumb)
        model.beginSlider()
    }
    func set(_ value: Int, on thumb: HueThumb) {
        let value = min(360, max(0, value))
        thumb.hue = value
        thumb.positionHue = Double(value)
        position()
        thumb.needsDisplay = true
        model.edit { recipe in
            recipe.look = .custom
            if thumb.isStart { recipe.gradientFrom = value } else { recipe.gradientTo = value }
        }
    }
    func pointer(_ event: NSEvent, on thumb: HueThumb) {
        let x = convert(event.locationInWindow, from: nil).x
        set(Int(((x - 14) / max(1, bounds.width - 28) * 360).rounded()), on: thumb)
    }
    func keyboard(delta: Int, on thumb: HueThumb) {
        stopHandleAnimation()
        if !keyboardEditing {
            keyboardEditing = true
        }
        // Undo/Reset may have ended the model's edit while this 500 ms burst
        // was still pending. beginSlider is idempotent and starts a fresh group.
        model.beginSlider()
        set(thumb.hue + delta, on: thumb)
        burst?.cancel()
        burst = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.endKeyboardBurst()
        }
    }
    func endKeyboardBurst() {
        burst?.cancel()
        burst = nil
        if keyboardEditing {
            keyboardEditing = false
            model.endSlider()
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let track = NSRect(x: 0, y: bounds.midY - 11, width: bounds.width, height: 22)
        NSBezierPath(roundedRect: track, xRadius: 11, yRadius: 11).addClip()
        for x in 0..<Int(bounds.width) {
            let color = GradientSampler.endpoint(
                Int((min(1, max(0, Double(x - 14) / max(1, Double(bounds.width - 28)))) * 360).rounded()))
            NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1).setFill()
            NSRect(x: x, y: 0, width: 1, height: Int(bounds.height)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class HueThumb: NSView {
    weak var strip: HueStripView?
    weak var model: PanelModel?
    let isStart: Bool
    var hue = 0, positionHue = 0.0, enabled = true
    private let focusStroke = NativeFocusStroke()
    init(model: PanelModel, isStart: Bool) {
        self.model = model
        self.isStart = isStart
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        identifier = NSUserInterfaceItemIdentifier("ps.gradient-\(isStart ? "start" : "end")")
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(isStart ? "Gradient start" : "Gradient end")
        setAccessibilityMinValue(0)
        setAccessibilityMaxValue(360)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { enabled }
    override var canBecomeKeyView: Bool { enabled && !isHiddenOrHasHiddenAncestor }
    override func becomeFirstResponder() -> Bool {
        model?.focus = .control
        strip?.bringForward(self)
        needsDisplay = true
        return true
    }
    override func resignFirstResponder() -> Bool {
        strip?.endKeyboardBurst()
        needsDisplay = true
        return true
    }
    override func accessibilityValue() -> Any? { hue }
    override func accessibilityValueDescription() -> String? { "\(hue) degrees, \(GradientHues.name(hue))" }
    override func isAccessibilityEnabled() -> Bool { enabled }
    override func accessibilityPerformIncrement() -> Bool {
        guard enabled else { return false }
        strip?.keyboard(delta: 1, on: self)
        return true
    }
    override func accessibilityPerformDecrement() -> Bool {
        guard enabled else { return false }
        strip?.keyboard(delta: -1, on: self)
        return true
    }
    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        window?.makeFirstResponder(self)
        strip?.beginPointer(self)
        strip?.pointer(event, on: self)
    }
    override func mouseDragged(with event: NSEvent) { if enabled { strip?.pointer(event, on: self) } }
    override func mouseUp(with event: NSEvent) { model?.endSlider() }
    override func keyDown(with event: NSEvent) {
        if [123, 124, 125, 126].contains(event.keyCode) {
            let amount = event.modifierFlags.contains(.shift) ? 10 : 1
            strip?.keyboard(delta: [124, 126].contains(event.keyCode) ? amount : -amount, on: self)
        } else if [51, 117].contains(event.keyCode) {
            return
        } else {
            super.keyDown(with: event)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        let color = GradientSampler.endpoint(hue)
        NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1).setFill()
        let visible = bounds.insetBy(dx: 5, dy: 5)
        let path = NSBezierPath(ovalIn: visible.insetBy(dx: 1, dy: 1))
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = .black.withAlphaComponent(0.25)
        shadow.set()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.setStroke()
        path.lineWidth = 2
        path.stroke()
        focusStroke.update(
            in: self, rect: visible.insetBy(dx: 1, dy: 1), radius: nil,
            visible: enabled && model?.keyboardFocus == true && window?.firstResponder === self)
    }
}
