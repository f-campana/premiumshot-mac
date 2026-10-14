import AppKit
import PremiumShotCore
import SwiftUI

/// A floating, non-activating window that still takes keyboard input, so summoning it never changes which app
/// is frontmost and dismissing it leaves that app exactly as it was.
@MainActor
final class FloatingPanel: NSPanel {
    /// Return true when the event was handled.
    var onKey: ((NSEvent) -> Bool)?
    /// Esc arrives as `cancelOperation` when nothing else handles it.
    var onCancel: (() -> Void)?

    init(size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // elevation is drawn by ShadowWindow so it can match the mock
        isMovable = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        title = "PremiumShot"
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKey?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Draws only the card's shadow, in a separate click-through window behind the card. Because it ignores mouse
/// events, clicks around the card reach whatever is underneath, and nothing dark is drawn under the translucent card.
@MainActor
final class ShadowWindow: NSWindow {
    static let padding: CGFloat = 80

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = ShadowView()
    }

    // This click-through padding may cross the menu bar. Constraining it like a
    // regular window shifts the entire shadow downward while the card stays put.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func place(around card: NSRect, weight: PanelWeight) {
        setFrame(card.insetBy(dx: -Self.padding, dy: -Self.padding), display: false)
        (contentView as? ShadowView)?.configure(
            card: NSRect(x: Self.padding, y: Self.padding, width: card.width, height: card.height),
            weight: weight)
    }
}

final class ShadowView: NSView {
    override var isFlipped: Bool { false }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Each shadow is (offsetY, blur, spread, alpha), from the mock's two weights.
    func configure(card: NSRect, weight: PanelWeight) {
        let layers: [(Double, Double, Double, Double)] =
            weight == .light
            ? [(14, 34, -14, 0.32), (2, 8, -2, 0.16)]
            : [(34, 80, -16, 0.45), (12, 30, -10, 0.26)]
        layer?.sublayers = nil
        let colour = NSColor(srgbRed: 6 / 255, green: 10 / 255, blue: 26 / 255, alpha: 1).cgColor
        for (offsetY, blur, spread, alpha) in layers {
            let shadow = CALayer()
            shadow.frame = bounds
            let rect = card.insetBy(dx: -spread, dy: -spread)
            shadow.shadowPath = CGPath(
                roundedRect: rect, cornerWidth: PanelMetrics.cornerRadius + spread,
                cornerHeight: PanelMetrics.cornerRadius + spread, transform: nil)
            shadow.shadowColor = colour
            shadow.shadowOpacity = Float(alpha)
            shadow.shadowRadius = blur / 2
            shadow.shadowOffset = CGSize(width: 0, height: -offsetY)
            layer?.addSublayer(shadow)
        }
        // Hide everything under the card itself: the card is translucent and must show the desktop, not shadow.
        let mask = CAShapeLayer()
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addPath(
            CGPath(
                roundedRect: card, cornerWidth: PanelMetrics.cornerRadius,
                cornerHeight: PanelMetrics.cornerRadius, transform: nil))
        mask.path = path
        mask.fillRule = .evenOdd
        layer?.mask = mask
    }
}

/// Owns the card window and its shadow window, positions them on the screen under the pointer, and routes keys.
@MainActor
public final class PanelController: NSObject, NSWindowDelegate {
    public let model: PanelModel
    private let panel: FloatingPanel
    private let shadow = ShadowWindow()
    private var outsideClickMonitor: Any?
    private let presentation = PanelPresentation()
    private let sharedPreview = SharedPreviewView(frame: .zero)
    private var animator: PanelAnimator!
    private var transitionBitmap: CGImage?
    private var host: NSHostingView<PanelView>!
    private var keyLoopTask: Task<Void, Never>?
    private var anchorFrame = NSRect.zero
    private var inspectFrame = NSRect.zero
    private var outsideGesture = OutsideGesture()
    private var watchdog: Task<Void, Never>?
    private var localMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    public private(set) var isVisible = false

    public init(model: PanelModel) {
        self.model = model
        panel = FloatingPanel(size: PanelMetrics.card)
        super.init()
        panel.delegate = self

        let effect = PanelMaterialView(model: model)
        effect.onDragEligibility = { [weak self] in self?.outsideGesture.classify(eligible: $0) }
        effect.onDragEnd = { [weak self] in
            self?.outsideGesture.cancel()
            self?.watchdog?.cancel()
        }
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: PanelMetrics.cornerRadius)
        host = NSHostingView(rootView: PanelView(model: model, presentation: presentation))
        host.sizingOptions = []
        host.frame = effect.bounds
        host.autoresizingMask = []
        effect.addSubview(host)
        effect.wantsLayer = true
        effect.layer?.masksToBounds = true
        sharedPreview.autoresizingMask = [.width, .height]
        effect.addSubview(sharedPreview)
        panel.contentView = effect
        animator = PanelAnimator(window: panel, state: presentation) { [weak self] in self?.present($0) }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenChanged() }
        }
        panel.onKey = { [weak self] event in self?.handle(event) ?? false }
        panel.onCancel = { [weak self] in self?.escape() }
        model.onPresentationChange = { [weak self] in self?.updatePresentation() }
        model.onPresentationSnap = { [weak self] in self?.animator.snap() }
        model.onKeyLoopChange = { [weak self] in self?.scheduleKeyLoop() }
        model.onFinishWelcome = { [weak self] in self?.hide() }
        model.onFocusPreview = { [weak self] in
            guard let expected = self?.model.state.token else { return }
            Task { @MainActor in
                await Task.yield()
                guard let self, self.model.isReady, self.model.state.token == expected,
                    self.model.focus == .preview
                else { return }
                if let preview = Self.findPreview(in: self.panel.contentView) {
                    self.panel.makeFirstResponder(preview)
                }
            }
        }
    }

    public func toggle() { isVisible ? hide() : show() }

    public func showWelcome() {
        if isVisible { hide() }
        show(welcome: true)
    }

    public func show(welcome: Bool = false) {
        guard !isVisible else { return }
        model.backingScale = Self.screenUnderPointer()?.backingScaleFactor ?? 2
        if welcome { model.showWelcome() } else { model.summon() }
        let screen = Self.screenUnderPointer()
        let area = screen?.visibleFrame ?? .zero
        let card = PanelPlacement.clamp(Self.cardFrame(on: screen), to: area)
        model.canExpand = area.width >= 868 && area.height >= 436
        anchorFrame = card
        animator.reset(PanelPose(card: card), mode: .compact)
        panel.addChildWindow(shadow, ordered: .below)
        panel.makeKeyAndOrderFront(nil)  // no NSApp.activate: the previous app stays frontmost
        isVisible = true
        panel.autorecalculatesKeyViewLoop = welcome
        if let preview = Self.findPreview(in: panel.contentView) {
            panel.makeFirstResponder(preview)
        } else {
            panel.makeFirstResponder(panel.contentView?.subviews.first)
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 0
            shadow.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
                shadow.animator().alphaValue = 1
            }
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged, .leftMouseUp,
        ]) { [weak self] event in
            MainActor.assumeIsolated { self?.outsideEvent(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown])
        { [weak self] event in
            var swallow = false
            MainActor.assumeIsolated {
                self?.model.keyboardFocus = event.type == .keyDown
                Self.refreshFocus(in: self?.panel.contentView)
                if event.type == .keyDown, event.modifierFlags.contains(.command), let self,
                    event.window === self.panel || (event.window == nil && NSApp.keyWindow === self.panel)
                {
                    // Hosting views may consume menu commands before NSWindow sees them.
                    // Route our panel's commands once, before responder dispatch, then consume the event.
                    swallow = self.handle(event)
                }
                if let self,
                    self.outsideGesture.phase != .idle && event.type == .keyDown && event.keyCode == 53
                {
                    self.outsideGesture.cancel()
                    self.model.dropTarget = false
                    swallow = true
                }
            }
            return swallow ? nil : event
        }

    }

    public func hide() {
        guard isVisible else { return }
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        watchdog?.cancel()
        outsideGesture.cancel()
        animator.cancel()
        transitionBitmap = nil
        sharedPreview.place(image: nil, rect: .zero)
        model.dismiss()
        panel.alphaValue = 1
        shadow.alphaValue = 1
        panel.removeChildWindow(shadow)
        shadow.orderOut(nil)
        panel.orderOut(nil)
        isVisible = false
    }

    #if DEBUG
    /// Dev only: writes the card's content to a PNG (used by `--snapshot`). Behind-window blur is not captured.
    public func snapshot(to url: URL) -> Bool {
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }

    /// Companion to the dev snapshot: these are runtime bounds, not inferred PNG dimensions.
    public func snapshotLayout(to url: URL) throws {
        func values(_ rect: NSRect) -> [Double] { [rect.minX, rect.minY, rect.width, rect.height] }
        var metrics = [
            "card": values(panel.frame), "content": values(panel.contentView?.bounds ?? .zero),
            "host": values(host.frame), "shadow": values(shadow.frame),
            "shadowCard": values(shadow.frame.insetBy(dx: 80, dy: 80)),
        ]
        if let content = panel.contentView, let canvas = Self.findInspect(in: content) {
            let well = content.convert(canvas.bounds, from: canvas)
            metrics["inspectWell"] = values(well)
            metrics["inspectBottomGap"] = [content.isFlipped ? content.bounds.maxY - well.maxY : well.minY]
        }
        try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys]).write(
            to: url)
    }
    #endif

    private func escape() {
        if presentation.active && presentation.sharedImage {
            model.toggleInspect()
        } else {
            model.isInspecting ? model.closeInspect() : hide()
        }
    }

    func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([
            .capsLock, .numericPad, .function,
        ])
        let command = flags.contains(.command)
        // A plain SwiftUI button can leave AppKit's responder on the preview after a click.
        // Both focus records must agree before destructive or preview-only keys are routed.
        let previewFocused = panel.firstResponder is PreviewCanvas && model.focus == .preview
        if event.keyCode == 53 {
            escape()
            return true
        }
        if model.isWelcoming { return false }
        if command {
            // Preserve native editing commands in any field owned by the system.
            guard !(panel.firstResponder is NSTextView) else { return false }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                Task { await model.copy() }
                return true
            case "s":
                Task { await model.save() }
                return true
            case "v":
                model.paste()
                return true
            case "z":
                flags.contains(.shift) ? model.redo() : model.undo()
                return true
            default: return false
            }
        }
        if model.isInspecting { return false }
        if KeyRouting.shouldRemove(
            keyCode: event.keyCode, hasModifiers: !flags.isEmpty, previewFocused: previewFocused,
            inspecting: false)
        {
            model.removeScreenshot()
            panel.makeFirstResponder(nil)
            return true
        }
        guard flags.isEmpty else { return false }
        if event.keyCode == 49 && presentation.active && presentation.sharedImage {
            model.toggleInspect()
            return true
        }
        if event.charactersIgnoringModifiers?.lowercased() == "e" {
            model.toggleDrawer()
            return model.isReady
        }
        switch event.keyCode {
        case 36 where previewFocused, 76 where previewFocused:
            Task { await model.copy() }
            return true
        case 49 where previewFocused:
            model.toggleInspect()
            return true
        case 123 where previewFocused, 124 where previewFocused:
            model.cycleLook(event.keyCode == 123 ? -1 : 1)
            return true
        default: return false
        }
    }
    private func scheduleKeyLoop() {
        keyLoopTask?.cancel()
        keyLoopTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled, self.isVisible, !self.model.isInspecting,
                !self.model.isWelcoming,
                let root = self.panel.contentView
            else { return }
            _ = PanelKeyLoop.configure(root: root, window: self.panel)
        }
    }
    private static func findPreview(in view: NSView?) -> PreviewCanvas? {
        guard let view else { return nil }
        if let preview = view as? PreviewCanvas { return preview }
        for child in view.subviews { if let found = findPreview(in: child) { return found } }
        return nil
    }
    private static func findInspect(in view: NSView?) -> InspectCanvas? {
        guard let view else { return nil }
        if let canvas = view as? InspectCanvas { return canvas }
        return view.subviews.lazy.compactMap { findInspect(in: $0) }.first
    }
    private static func refreshFocus(in view: NSView?) {
        guard let view else { return }
        if view is NSControl || view is PreviewCanvas || view is HueThumb { view.needsDisplay = true }
        view.subviews.forEach { refreshFocus(in: $0) }
    }
    private func updatePresentation() {
        guard isVisible else { return }
        if !model.isReady {
            let token = model.state.token
            Task { [weak self] in
                await Task.yield()
                guard let self, self.isVisible, self.model.state.token == token, !self.model.isReady else {
                    return
                }
                self.panel.makeFirstResponder(self.panel.contentView?.subviews.first)
            }
        }
        let area = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchorFrame
        let target: NSRect
        if model.isInspecting {
            keyLoopTask?.cancel()
            panel.autorecalculatesKeyViewLoop = true
            let size = NSSize(width: min(960, area.width - 48), height: min(608, area.height - 48))
            presentation.inspectSize = size
            let candidate = NSRect(
                x: panel.frame.midX - size.width / 2, y: panel.frame.midY - size.height / 2,
                width: size.width,
                height: size.height)
            if !presentation.sharedImage || inspectFrame.size != size {
                inspectFrame = PanelPlacement.clamp(candidate, to: area)
            }
            target = PanelPlacement.clamp(inspectFrame, to: area)
        } else {
            scheduleKeyLoop()
            let width: CGFloat = model.isExpanded ? 844 : 600
            target = PanelPlacement.clamp(
                NSRect(
                    x: anchorFrame.minX, y: anchorFrame.minY, width: width, height: 412), to: area)
        }
        let mode: PanelMode = model.isInspecting ? .inspect : (model.isExpanded ? .adjust : .compact)
        let inspectTransition = mode == .inspect || presentation.mode == .inspect || presentation.sharedImage
        let bitmap = transitionBitmap ?? model.preview
        let targetImage = imageRect(in: target, inspecting: mode == .inspect)
        if !animator.state.active {
            var start = animator.pose
            start.image = imageRect(in: panel.frame, inspecting: presentation.mode == .inspect)
            animator.reset(start, mode: presentation.mode)
        }
        if inspectTransition { transitionBitmap = bitmap }
        let pose = PanelPose(
            card: target, image: targetImage, compact: mode == .inspect ? 0 : 1,
            drawer: mode == .adjust ? 1 : 0, inspect: mode == .inspect ? 1 : 0)
        let duration = inspectTransition ? (mode == .inspect ? 0.32 : 0.26) : (mode == .adjust ? 0.28 : 0.22)
        animator.begin(pose, mode: mode, duration: duration, sharedImage: inspectTransition)
    }

    private func present(_ pose: PanelPose) {
        placeCard(pose.card, weight: Preferences.panelWeight(model.defaults))
        sharedPreview.showsTransparency = model.recipe.look == .clear
        // The window reveals a fixed endpoint layout. Its changing size never
        // becomes a proposal to SwiftUI, which would reflow or centre wide content.
        let content = panel.contentView?.bounds ?? .zero
        let size =
            presentation.active
            ? NSSize(
                width: max(
                    presentation.showDrawer ? 844 : 600,
                    presentation.showInspect ? presentation.inspectSize.width : 0),
                height: presentation.showInspect ? presentation.inspectSize.height : 412)
            : pose.card.size
        host?.frame = NSRect(x: 0, y: content.height - size.height, width: size.width, height: size.height)
        sharedPreview.frame = panel.contentView?.bounds ?? .zero
        let rect = NSRect(
            x: pose.image.minX - panel.frame.minX,
            y: panel.frame.maxY - pose.image.maxY,
            width: pose.image.width, height: pose.image.height)
        if presentation.sharedImage {
            sharedPreview.place(image: transitionBitmap, rect: rect)
        } else if transitionBitmap != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            sharedPreview.revealUnderlyingImage(at: rect)
            transitionBitmap = nil
        } else if !presentation.active {
            sharedPreview.place(image: nil, rect: .zero)
        }
        if !presentation.active {
            transitionBitmap = nil
            if model.isInspecting { Self.findInspect(in: panel.contentView)?.finishTransition() }
            scheduleKeyLoop()
        }
    }

    private func placeCard(_ rect: NSRect, weight: PanelWeight) {
        panel.setFrame(rect, display: true)
        shadow.place(around: panel.frame, weight: weight)
    }

    /// Global bitmap bounds for a fixed endpoint layout, independent of intermediate window sizes.
    private func imageRect(in card: NSRect, inspecting: Bool) -> NSRect {
        guard let layout = model.layout else { return .zero }
        let area =
            inspecting
            ? NSRect(x: 28, y: 68, width: card.width - 56, height: card.height - 96)
            : NSRect(x: 28, y: 26, width: 544, height: 300)
        let ratio = min(
            area.width / CGFloat(layout.width), area.height / CGFloat(layout.height),
            inspecting ? 4 / model.backingScale : .infinity)
        let size = NSSize(width: CGFloat(layout.width) * ratio, height: CGFloat(layout.height) * ratio)
        return NSRect(
            x: card.minX + area.midX - size.width / 2,
            y: card.maxY - area.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func outsideEvent(_ event: NSEvent) {
        let board = NSPasteboard(name: .drag)
        switch event.type {
        case .rightMouseDown, .otherMouseDown:
            hide()
            return
        case .leftMouseDown:
            outsideGesture.press(at: NSEvent.mouseLocation, pasteboardCount: board.changeCount)
        case .leftMouseDragged:
            outsideGesture.move(to: NSEvent.mouseLocation)
            if outsideGesture.phase == .unknown && board.changeCount != outsideGesture.pasteboardCount {
                outsideGesture.classify(eligible: PanelMaterialView.eligible(board))
            }
        case .leftMouseUp:
            if outsideGesture.end() { hide() }
            model.dropTarget = false
        default: return
        }
        watchdog?.cancel()
        guard outsideGesture.phase != .idle else { return }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                // A stationary held drag is still active. Never dismiss just because motion stopped.
                guard NSEvent.pressedMouseButtons & 1 == 0 else { continue }
                if self.outsideGesture.end() { self.hide() }
                self.model.dropTarget = false
                return
            }
        }
    }
    private func screenChanged() {
        guard isVisible else { return }
        let screen = panel.screen ?? Self.screenUnderPointer()
        model.backingScale = screen?.backingScaleFactor ?? 2
        model.constrainExpansion(
            to: (screen?.visibleFrame.width ?? 0) >= 868 && (screen?.visibleFrame.height ?? 0) >= 436)
        anchorFrame = PanelPlacement.clamp(
            Self.cardFrame(on: screen), to: screen?.visibleFrame ?? anchorFrame)
        updatePresentation()
    }

    // MARK: Placement

    static func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    /// Centred horizontally, 16% of the screen height below the top of the usable area (the mock's 112 of 700).
    static func cardFrame(on screen: NSScreen?) -> NSRect {
        let size = PanelMetrics.card
        let area = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let top = min(160, max(64, area.height * 0.16))
        return NSRect(
            x: (area.midX - size.width / 2).rounded(), y: (area.maxY - top - size.height).rounded(),
            width: size.width, height: size.height)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
