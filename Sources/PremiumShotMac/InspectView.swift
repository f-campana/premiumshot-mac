import AppKit
import PremiumShotCore
import SwiftUI

struct InspectView: View {
    let model: PanelModel
    var presentation: PanelPresentation?
    var wellTone: WellTone
    @State private var zoom = Zoom()
    @State private var command: InspectCommand = .fit
    @State private var commandID = 0
    private var atFit: Bool { abs(zoom.scale - zoom.fitScale) < 0.001 }
    init(
        model: PanelModel, targetSize: CGSize? = nil, presentation: PanelPresentation? = nil,
        wellTone: WellTone = PanelTheme.wellTone
    ) {
        self.model = model
        self.presentation = presentation
        self.wellTone = wellTone
        var initial = Zoom()
        if let l = model.layout {
            let size = targetSize ?? CGSize(width: 960, height: 608)
            initial.configure(
                width: Double(l.width), height: Double(l.height),
                viewportWidth: size.width - 56, viewportHeight: size.height - 96,
                backingScale: Double(model.backingScale), fit: true)
        }
        _zoom = State(initialValue: initial)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Fit") {
                    command = .fit
                    commandID += 1
                }.padding(.horizontal, 8).padding(.vertical, 5)
                    .disabled(presentation?.active == true)
                    .background(
                        Color.primary.opacity(atFit ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6)
                    )
                    .panelFocus(model: model, radius: 6)
                Button("Actual size") {
                    command = .actual
                    commandID += 1
                }.padding(.horizontal, 8).padding(.vertical, 5)
                    .disabled(presentation?.active == true)
                    .background(
                        Color.primary.opacity(!atFit && abs(zoom.scale - 1) < 0.001 ? 0.08 : 0),
                        in: RoundedRectangle(cornerRadius: 6)
                    ).panelFocus(model: model, radius: 6)
                if let l = model.layout {
                    Text(
                        "\(l.width.formatted()) × \(l.height.formatted()) px · \(atFit ? "fit to window · " : "")\(Int((zoom.scale*100).rounded()))%"
                    )
                    .monospacedDigit().foregroundStyle(PanelTheme.informationStyle).lineLimit(1)
                }
                Spacer()
                Text("Swipe ↑ to zoom · Drag to pan").foregroundStyle(PanelTheme.informationStyle)
                    .lineLimit(1).layoutPriority(-1)
                Button("Done") { model.toggleInspect() }.panelFocus(model: model).keyboardShortcut(
                    .escape, modifiers: [])
            }.font(.system(size: 12)).buttonStyle(.plain).padding(.horizontal, 20).frame(height: 52)
            InspectSurface(
                model: model, zoom: $zoom, command: command, commandID: commandID,
                presentation: presentation
            )
            .opacity(presentation?.sharedImage == true ? 0 : 1)
            .background(WellSurface(tone: wellTone))
            .clipShape(RoundedRectangle(cornerRadius: 14)).padding([.horizontal, .bottom], 12)
        }
    }
}

enum InspectCommand { case fit, actual }
struct InspectSurface: NSViewRepresentable {
    let model: PanelModel
    @Binding var zoom: Zoom
    let command: InspectCommand, commandID: Int
    var presentation: PanelPresentation? = nil
    func makeNSView(context: Context) -> InspectCanvas { InspectCanvas(model: model) }
    func updateNSView(_ view: InspectCanvas, context: Context) {
        view.presentation = presentation
        view.onZoom = { if zoom != $0 { zoom = $0 } }
        view.refresh(command: command, commandID: commandID)
    }
}

final class InspectCanvas: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    let model: PanelModel
    var presentation: PanelPresentation?
    var onZoom: ((Zoom) -> Void)?
    private(set) var zoom = Zoom()
    private let imageLayer = CALayer()
    private let previousImageLayer = CALayer()
    private var pendingFull: CGImage?
    private var token: WorkToken?, image: CGImage?, imageTask: Task<Void, Never>?
    private var lastCommand = -1
    private var dragPoint: NSPoint?
    private var entryFocusTask: Task<Void, Never>?
    override var acceptsFirstResponder: Bool { true }
    init(model: PanelModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        imageLayer.contentsGravity = .resize
        layer?.addSublayer(imageLayer)
        layer?.addSublayer(previousImageLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Inspect screenshot")
        setAccessibilityHelp("Swipe up to zoom in. Z toggles actual size. Escape returns to the panel.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        entryFocusTask?.cancel()
        guard let attachedWindow = window else { return }
        // SwiftUI attaches the representable after its first update. Hand off once,
        // after attachment, rather than stealing focus on every zoom/render refresh.
        entryFocusTask = Task { @MainActor [weak self, weak attachedWindow] in
            await Task.yield()
            guard let self, let attachedWindow, self.window === attachedWindow,
                self.model.isInspecting, !Task.isCancelled
            else { return }
            attachedWindow.makeFirstResponder(self)
        }
    }
    override func layout() {
        super.layout()
        configure(fit: token == nil || abs(zoom.scale - zoom.fitScale) < 0.001)
        paint()
    }
    private func configure(fit: Bool) {
        guard let layout = model.layout else { return }
        zoom.configure(
            width: Double(layout.width), height: Double(layout.height),
            viewportWidth: Double(bounds.width) - 32, viewportHeight: Double(bounds.height) - 32,
            backingScale: Double(model.backingScale), fit: fit)
    }
    func refresh(command: InspectCommand, commandID: Int) {
        if model.frame == nil {
            imageTask?.cancel()
            token = nil
            image = nil
            pendingFull = nil
        }
        if let current = model.frame?.token, current == model.state.token, token != current {
            let isNew = token?.sessionID != model.state.token.sessionID
            token = model.state.token
            image = model.preview
            pendingFull = nil
            previousImageLayer.removeAllAnimations()
            previousImageLayer.contents = nil
            configure(fit: isNew || abs(zoom.scale - zoom.fitScale) < 0.001)
            imageTask?.cancel()
            let expected = token
            imageTask = Task { [weak self, weak model] in
                guard let model, let full = await model.fullImage(), let self, self.token == expected,
                    !Task.isCancelled
                else { return }
                self.pendingFull = full
                self.installFullIfReady()
            }
        }
        if lastCommand != commandID {
            lastCommand = commandID
            configure(fit: command == .fit)
            if command == .actual { zoom.zoom(to: 1) }
        }
        installFullIfReady()
        paint()
    }
    private func installFullIfReady() {
        guard presentation?.active != true, let full = pendingFull else { return }
        pendingFull = nil
        let previous = image
        image = full
        paint()
        guard let previous, previous !== full,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previousImageLayer.frame = imageLayer.frame
        previousImageLayer.contents = previous
        previousImageLayer.opacity = 0
        CATransaction.commit()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.1
        previousImageLayer.add(fade, forKey: "resolution")
    }
    func finishTransition() {
        installFullIfReady()
        paint()
    }
    private func paint() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w = zoom.imageWidth * zoom.scale
        let h = zoom.imageHeight * zoom.scale
        var x = Double(bounds.midX) - w / 2 + zoom.x
        var y = Double(bounds.midY) - h / 2 + zoom.y
        if abs(zoom.scale - 1) < 0.001 {
            // Odd output dimensions otherwise land half a backing pixel off-grid at 100%.
            let backing = Double(model.backingScale)
            x = (x * backing).rounded() / backing
            y = (y * backing).rounded() / backing
        }
        imageLayer.frame = NSRect(
            x: x, y: y, width: w, height: h)
        previousImageLayer.frame = imageLayer.frame
        imageLayer.contents = image
        imageLayer.magnificationFilter = zoom.scale >= 1 ? .nearest : .linear
        imageLayer.minificationFilter = .trilinear
        CATransaction.commit()
        needsDisplay = true
        let snapshot = zoom
        Task { [weak self] in self?.onZoom?(snapshot) }
    }
    override func draw(_ dirtyRect: NSRect) {
        if model.recipe.look == .clear {
            let cell: CGFloat = 12
            NSColor.controlBackgroundColor.setFill()
            bounds.fill()
            NSColor.labelColor.withAlphaComponent(0.065).setFill()
            for y in stride(from: CGFloat(0), to: bounds.height, by: cell) {
                for x in stride(from: CGFloat(0), to: bounds.width, by: cell)
                where (Int(x / cell) + Int(y / cell)) % 2 == 0 {
                    NSRect(x: x, y: y, width: cell, height: cell).fill()
                }
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard presentation?.active != true else { return }
        window?.makeFirstResponder(self)
        dragPoint = convert(event.locationInWindow, from: nil)
    }
    override func mouseDragged(with event: NSEvent) {
        guard presentation?.active != true else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let before = dragPoint {
            zoom.pan(dx: point.x - before.x, dy: point.y - before.y)
            paint()
        }
        dragPoint = point
    }
    override func mouseUp(with event: NSEvent) { dragPoint = nil }
    private func anchor() -> NSPoint {
        let point = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        return NSPoint(x: point.x - bounds.midX, y: point.y - bounds.midY)
    }
    override func scrollWheel(with event: NSEvent) {
        guard presentation?.active != true else { return }
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            zoom.pan(dx: event.scrollingDeltaX, dy: 0)
        } else if let intent = Gestures.zoomIntent(
            scrollingDeltaY: event.scrollingDeltaY,
            directionInvertedFromDevice: event.isDirectionInvertedFromDevice)
        {
            let point = anchor()
            let delta = min(40, abs(event.scrollingDeltaY)) * 0.006 * (intent == .zoomIn ? 1.0 : -1.0)
            zoom.zoom(to: zoom.scale * exp(delta), anchorX: point.x, anchorY: point.y)
        }
        paint()
    }
    override func magnify(with event: NSEvent) {
        guard presentation?.active != true else { return }
        let point = anchor()
        zoom.zoom(to: zoom.scale * (1 + event.magnification), anchorX: point.x, anchorY: point.y)
        paint()
    }
    override func keyDown(with event: NSEvent) {
        if [24, 27, 123, 124, 125, 126].contains(event.keyCode)
            || event.charactersIgnoringModifiers?.lowercased() == "z"
        {
            model.onPresentationSnap?()
        }
        if event.charactersIgnoringModifiers?.lowercased() == "z",
            !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        {
            super.keyDown(with: event)
            return
        }
        if event.charactersIgnoringModifiers?.lowercased() == "z" {
            zoom.zoom(to: abs(zoom.scale - 1) < 0.001 ? zoom.fitScale : 1)
            paint()
            return
        }
        switch event.keyCode {
        case 24: zoom.zoom(to: zoom.scale * 1.15)
        case 27: zoom.zoom(to: zoom.scale / 1.15)
        case 123, 124:
            if abs(zoom.scale - zoom.fitScale) < 0.001 {
                model.cycleLook(event.keyCode == 123 ? -1 : 1)
            } else {
                zoom.pan(dx: event.keyCode == 123 ? 40 : -40, dy: 0)
            }
        case 125, 126: zoom.pan(dx: 0, dy: event.keyCode == 125 ? 40 : -40)
        case 49, 53:
            model.closeInspect()
            return
        case 51, 117: return
        default:
            super.keyDown(with: event)
            return
        }
        paint()
    }
}
