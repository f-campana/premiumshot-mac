import AppKit
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
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                 // elevation is drawn by ShadowWindow so it can match the mock
        isMovable = false
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) { if onKey?(event) == true { return }; super.keyDown(with: event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { if onKey?(event) == true { return true }; return super.performKeyEquivalent(with: event) }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Draws only the card's shadow, in a separate click-through window behind the card. Because it ignores mouse
/// events, clicks around the card reach whatever is underneath, and nothing dark is drawn under the translucent card.
@MainActor
final class ShadowWindow: NSWindow {
    static let padding: CGFloat = 80

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false; ignoresMouseEvents = true
        level = .floating; collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false; animationBehavior = .none
        contentView = ShadowView()
    }

    func place(around card: NSRect, weight: PanelWeight) {
        setFrame(card.insetBy(dx: -Self.padding, dy: -Self.padding), display: false)
        (contentView as? ShadowView)?.configure(card: NSRect(x: Self.padding, y: Self.padding, width: card.width, height: card.height), weight: weight)
    }
}

final class ShadowView: NSView {
    override var isFlipped: Bool { false }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }

    /// Each shadow is (offsetY, blur, spread, alpha), from the mock's two weights.
    func configure(card: NSRect, weight: PanelWeight) {
        let layers: [(Double, Double, Double, Double)] = weight == .light
            ? [(14, 34, -14, 0.32), (2, 8, -2, 0.16)]
            : [(34, 80, -16, 0.45), (12, 30, -10, 0.26)]
        layer?.sublayers = nil
        let colour = NSColor(srgbRed: 6 / 255, green: 10 / 255, blue: 26 / 255, alpha: 1).cgColor
        for (offsetY, blur, spread, alpha) in layers {
            let shadow = CALayer()
            shadow.frame = bounds
            let rect = card.insetBy(dx: -spread, dy: -spread)
            shadow.shadowPath = CGPath(roundedRect: rect, cornerWidth: PanelMetrics.cornerRadius + spread, cornerHeight: PanelMetrics.cornerRadius + spread, transform: nil)
            shadow.shadowColor = colour; shadow.shadowOpacity = Float(alpha)
            shadow.shadowRadius = blur / 2; shadow.shadowOffset = CGSize(width: 0, height: -offsetY)
            layer?.addSublayer(shadow)
        }
        // Hide everything under the card itself: the card is translucent and must show the desktop, not shadow.
        let mask = CAShapeLayer()
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addPath(CGPath(roundedRect: card, cornerWidth: PanelMetrics.cornerRadius, cornerHeight: PanelMetrics.cornerRadius, transform: nil))
        mask.path = path; mask.fillRule = .evenOdd
        layer?.mask = mask
    }
}

/// Owns the card window and its shadow window, positions them on the screen under the pointer, and routes keys.
@MainActor
public final class PanelController {
    public let model: PanelModel
    private let panel: FloatingPanel
    private let shadow = ShadowWindow()
    private var outsideClickMonitor: Any?
    public private(set) var isVisible = false

    public init(model: PanelModel) {
        self.model = model
        panel = FloatingPanel(size: PanelMetrics.card)

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: PanelMetrics.card))
        effect.material = .popover; effect.blendingMode = .behindWindow; effect.state = .active
        effect.maskImage = Self.roundedMask(radius: PanelMetrics.cornerRadius)
        let host = NSHostingView(rootView: PanelView(model: model))
        host.frame = effect.bounds; host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        panel.contentView = effect

        panel.onKey = { [weak self] event in self?.handle(event) ?? false }
        panel.onCancel = { [weak self] in self?.hide() }
    }

    public func toggle() { isVisible ? hide() : show() }

    public func show() {
        guard !isVisible else { return }
        model.backingScale = Self.screenUnderPointer()?.backingScaleFactor ?? 2
        model.summon()
        let card = Self.cardFrame(on: Self.screenUnderPointer())
        panel.setFrame(card, display: true)
        shadow.place(around: card, weight: Preferences.panelWeight())
        panel.addChildWindow(shadow, ordered: .below)
        panel.makeKeyAndOrderFront(nil)           // no NSApp.activate: the previous app stays frontmost
        isVisible = true
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    public func hide() {
        guard isVisible else { return }
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor); outsideClickMonitor = nil }
        panel.removeChildWindow(shadow)
        shadow.orderOut(nil); panel.orderOut(nil)
        isVisible = false
    }

    /// Dev only: writes the card's content to a PNG (used by `--snapshot`). Behind-window blur is not captured.
    public func snapshot(to url: URL) -> Bool {
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        switch event.keyCode {
        case 53: hide(); return true                                                              // Esc
        case 36, 76: Task { await model.copy() }; return true                                     // Return, Enter
        case 8 where command: Task { await model.copy() }; return true                            // ⌘C
        default: return false
        }
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
        return NSRect(x: (area.midX - size.width / 2).rounded(), y: (area.maxY - top - size.height).rounded(), width: size.width, height: size.height)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill(); return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
