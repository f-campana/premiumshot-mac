import AppKit
import PremiumShotCore
import SwiftUI

struct PreviewSurface: NSViewRepresentable {
    let model: PanelModel
    func makeNSView(context: Context) -> PreviewCanvas { PreviewCanvas(model: model) }
    func updateNSView(_ view: PreviewCanvas, context: Context) {
        let _ = model.preview
        let _ = model.keyboardFocus
        view.refresh()
    }
}

/// An actual AppKit responder gives the non-activating panel reliable focus, drop and dragging semantics.
final class PreviewCanvas: NSView, NSDraggingSource {
    let model: PanelModel
    private let imageLayer = CALayer()
    private var displayed: PreviewFrame?
    private var down: NSPoint?, latestDrag: NSEvent?, dragURL: URL?, thresholdTime: Date?
    private var dragToken: WorkToken?
    private var dragTask: Task<Void, Never>?
    private var dragging = false
    private var lastCopy: UInt64 = 0
    override var acceptsFirstResponder: Bool { true }
    init(model: PanelModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.minificationFilter = .trilinear
        layer?.addSublayer(imageLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Screenshot preview")
        identifier = NSUserInterfaceItemIdentifier("ps.preview")
        setAccessibilityHelp("Space to inspect. Delete to remove. Drag to export.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var mouseDownCanMoveWindow: Bool { false }
    override func becomeFirstResponder() -> Bool {
        model.focus = .preview
        needsDisplay = true
        return true
    }
    override func resignFirstResponder() -> Bool {
        model.focus = .control
        needsDisplay = true
        return true
    }
    override func layout() {
        super.layout()
        positionImage()
    }
    private func positionImage() {
        guard let image = model.preview else {
            imageLayer.contents = nil
            return
        }
        let area = bounds.insetBy(dx: 16, dy: 14)
        let ratio = min(area.width / CGFloat(image.width), area.height / CGFloat(image.height))
        let size = NSSize(width: CGFloat(image.width) * ratio, height: CGFloat(image.height) * ratio)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = NSRect(
            x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width,
            height: size.height)
        CATransaction.commit()
    }
    func refresh() {
        let next = model.frame
        let newSession = displayed?.token.sessionID != next?.token.sessionID
        model.onKeyLoopChange?()
        if let old = displayed, let next, old.token.sessionID == next.token.sessionID,
            old.render.image !== next.render.image, old.recipe.look != next.recipe.look,
            old.render.layout.width == next.render.layout.width,
            old.render.layout.height == next.render.layout.height,
            old.render.layout.window == next.render.layout.window,
            model.presentationImage == nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        {
            let animation = CABasicAnimation(keyPath: "contents")
            animation.fromValue = old.render.image
            animation.toValue = next.render.image
            animation.duration = Preferences.panelWeight() == .light ? 0.2 : 0.3
            imageLayer.add(animation, forKey: "look")
        } else if next == nil || model.presentationImage != nil {
            imageLayer.removeAllAnimations()
        }
        displayed = next
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = model.preview
        CATransaction.commit()
        positionImage()
        needsDisplay = true
        if model.copySequence != lastCopy {
            lastCopy = model.copySequence
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { pulse() }
        }
        if newSession && model.focus == .preview && window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
    }
    private func pulse() {
        let ring = CAShapeLayer()
        ring.path = CGPath(
            roundedRect: imageLayer.frame.insetBy(dx: -4, dy: -4), cornerWidth: 6, cornerHeight: 6,
            transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor
        ring.lineWidth = 2
        layer?.addSublayer(ring)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.72
        ring.add(fade, forKey: "copied")
        ring.opacity = 0
        Task {
            try? await Task.sleep(for: .milliseconds(730))
            ring.removeFromSuperlayer()
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        if model.recipe.look == .clear, let image = model.preview {
            let rect = imageLayer.frame
            let cell: CGFloat = 10
            NSColor.controlBackgroundColor.setFill()
            rect.fill()
            NSColor.labelColor.withAlphaComponent(0.07).setFill()
            for row in 0...Int(rect.height / cell) {
                for col in 0...Int(rect.width / cell) where (row + col) % 2 == 0 {
                    NSRect(
                        x: rect.minX + CGFloat(col) * cell, y: rect.minY + CGFloat(row) * cell,
                        width: min(cell, rect.maxX - (rect.minX + CGFloat(col) * cell)),
                        height: min(cell, rect.maxY - (rect.minY + CGFloat(row) * cell))
                    ).fill()
                }
            }
            _ = image
        }
        if window?.firstResponder === self && model.keyboardFocus {
            NSColor.controlAccentColor.withAlphaComponent(0.5).setStroke()
            let path = NSBezierPath(
                roundedRect: imageLayer.frame.insetBy(dx: -4, dy: -4), xRadius: 6, yRadius: 6)
            path.lineWidth = 1
            path.stroke()
        }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        model.focus = .preview
        if event.clickCount == 2 {
            model.toggleInspect()
            return
        }
        down = convert(event.locationInWindow, from: nil)
        thresholdTime = nil
        dragURL = nil
        latestDrag = nil
        dragging = false
        let token = model.state.token
        dragToken = token
        dragTask?.cancel()
        dragTask = Task { [weak self, weak model] in
            guard let model, let url = await model.prepareDrag() else { return }
            guard let self, self.model.state.token == token, !Task.isCancelled else {
                DragTempFiles.remove(url)
                return
            }
            self.dragURL = url
            self.beginIfReady()
        }
    }
    override func mouseDragged(with event: NSEvent) {
        latestDrag = event
        beginIfReady()
    }
    private func beginIfReady() {
        guard !dragging, let down, let event = latestDrag, dragToken == model.state.token else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - down.x, point.y - down.y) >= 5 else { return }
        // The deadline starts at the drag threshold, not at mouse-down. Holding the
        // mouse before moving must still work when the PNG is already ready.
        if thresholdTime == nil { thresholdTime = Date() }
        guard Date().timeIntervalSince(thresholdTime!) <= 0.3 else {
            if dragURL == nil { model.notice("The image is still rendering. Try dragging again.") }
            return
        }
        guard let url = dragURL, let preview = model.preview else { return }
        dragging = true
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let image = NSImage(cgImage: preview, size: imageLayer.frame.size)
        item.setDraggingFrame(imageLayer.frame, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    override func mouseUp(with event: NSEvent) {
        if !dragging, let dragURL {
            DragTempFiles.remove(dragURL)
            self.dragURL = nil
        }
        down = nil
        thresholdTime = nil
        dragToken = nil
        latestDrag = nil
        dragTask?.cancel()
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation
    { .copy }
    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        // Successful destinations may consume the file asynchronously; retain those until launch cleanup.
        if operation.isEmpty, let dragURL { DragTempFiles.remove(dragURL) }
        dragURL = nil
        dragging = false
        down = nil
        latestDrag = nil
        dragToken = nil
    }
}
