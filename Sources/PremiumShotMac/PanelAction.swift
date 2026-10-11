import AppKit
import PremiumShotCore
import SwiftUI

enum PanelActionStyle {
    case quiet, primary, icon, roundIcon
    case swatch(LookID)
}

/// Native buttons make keyboard traversal explicit and keep disabled text legible.
struct PanelAction: NSViewRepresentable {
    let model: PanelModel
    let title: String
    var symbol: String? = nil
    let id: String
    var style: PanelActionStyle = .quiet
    var selected = false
    var keyEquivalent = ""
    let action: () -> Void
    func makeNSView(context: Context) -> ActionButton {
        let button = ActionButton(model: model)
        button.identifier = NSUserInterfaceItemIdentifier("ps.\(id)")
        return button
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ActionButton, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
    func updateNSView(_ button: ActionButton, context: Context) {
        button.title = title
        button.symbol = symbol
        button.style = style
        button.isEnabled = context.environment.isEnabled
        button.selected = selected
        button.keyEquivalent = keyEquivalent
        button.keyEquivalentModifierMask = []
        button.setAccessibilityValue(selected ? 1 : 0)
        button.setAccessibilityLabel(title)
        button.actionBody = action
        button.updateSwatch()
        button.needsDisplay = true
        model.onKeyLoopChange?()
    }
}

final class ActionButton: NSButton {
    weak var model: PanelModel?
    var symbol: String?, style: PanelActionStyle = .quiet, selected = false
    var actionBody: (() -> Void)?
    private let focusStroke = NativeFocusStroke()
    private var swatchImage: CGImage?, swatchRecipe: Recipe?
    init(model: PanelModel) {
        self.model = model
        super.init(frame: .zero)
        setButtonType(.momentaryChange)
        isBordered = false
        focusRingType = .none
        target = self
        action = #selector(pressed)
        font = .systemFont(ofSize: 13, weight: .medium)
    }
    required init?(coder: NSCoder) { fatalError() }
    // Labels are accessibility/action metadata, not the size of our custom drawing.
    // NSButton's cell otherwise forces Graphite and icon buttons wider than their SwiftUI frames.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
    override var mouseDownCanMoveWindow: Bool { false }
    // NSButton opts into material vibrancy, which remaps our full-colour raster swatches.
    override var allowsVibrancy: Bool { false }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
    override func becomeFirstResponder() -> Bool {
        if case .swatch = style { model?.focus = .look } else { model?.focus = .control }
        needsDisplay = true
        return true
    }
    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
    @objc private func pressed() { actionBody?() }
    func updateSwatch() {
        guard case .swatch(let id) = style else { return }
        var recipe = model?.recipe ?? .default
        recipe.look = id
        if swatchRecipe?.look == id
            && (id != .custom
                || (swatchRecipe?.gradientFrom == recipe.gradientFrom
                    && swatchRecipe?.gradientTo == recipe.gradientTo))
        {
            return
        }
        swatchRecipe = recipe
        swatchImage = try? Renderer.background(recipe: recipe, width: 96, height: 72)
    }
    override func draw(_ dirtyRect: NSRect) {
        let focused = model?.keyboardFocus == true && window?.firstResponder === self && isEnabled
        let isSwatch: Bool
        if case .swatch = style { isSwatch = true } else { isSwatch = false }
        let rect = bounds.insetBy(dx: isSwatch ? 3 : 3.5, dy: isSwatch ? 4 : 3.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: isSwatch ? 8 : 9, yRadius: isSwatch ? 8 : 9)
        var foreground = NSColor.labelColor
        switch style {
        case .primary:
            // Fixed opaque disabled colours avoid contrast depending on the desktop through material.
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let background =
                isEnabled
                ? NSColor.labelColor
                : NSColor(
                    srgbRed: dark ? 0.28 : 0.80, green: dark ? 0.28 : 0.80, blue: dark ? 0.30 : 0.82, alpha: 1
                )
            foreground =
                isEnabled
                ? .windowBackgroundColor
                : NSColor(
                    srgbRed: dark ? 0.88 : 0.30, green: dark ? 0.88 : 0.30, blue: dark ? 0.90 : 0.32, alpha: 1
                )
            background.setFill()
            path.fill()
        case .icon:
            NSColor.controlBackgroundColor.withAlphaComponent(0.55).setFill()
            path.fill()
        case .roundIcon:
            NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.10 : 0.06).setFill()
            NSBezierPath(ovalIn: bounds).fill()
        case .swatch(let id):
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            if id == .clear {
                NSColor.controlBackgroundColor.setFill()
                rect.fill()
                NSColor.labelColor.withAlphaComponent(0.16).setFill()
                for y in stride(from: rect.minY, to: rect.maxY, by: 5) {
                    for x in stride(from: rect.minX, to: rect.maxX, by: 5)
                    where (Int((x - rect.minX) / 5) + Int((y - rect.minY) / 5)) % 2 == 0 {
                        NSRect(x: x, y: y, width: 5, height: 5).fill()
                    }
                }
            } else if let image = swatchImage {
                NSImage(cgImage: image, size: rect.size).draw(in: rect)
            }
            NSGraphicsContext.restoreGraphicsState()
            NSColor.labelColor.withAlphaComponent(0.15).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            if selected && !focused {
                NSColor.labelColor.withAlphaComponent(isEnabled ? 0.85 : 0.65).setStroke()
                let selectedPath = NSBezierPath(
                    roundedRect: rect.insetBy(dx: -3.5, dy: -3.5), xRadius: 11.5, yRadius: 11.5)
                selectedPath.lineWidth = 1.5
                selectedPath.stroke()
            }
        case .quiet:
            if selected || isHighlighted {
                NSColor.labelColor.withAlphaComponent(0.08).setFill()
                path.fill()
            }
            if !isEnabled {
                let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                foreground = NSColor(
                    srgbRed: dark ? 0.76 : 0.38, green: dark ? 0.76 : 0.38, blue: dark ? 0.78 : 0.40, alpha: 1
                )
            }
        }
        if case .swatch = style {
        } else if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let size: CGFloat = {
                if case .roundIcon = style { return 16 }
                return 14
            }()
            let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
                .applying(.init(paletteColors: [foreground]))
            let configured = image.withSymbolConfiguration(configuration) ?? image
            configured.draw(
                in: NSRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size))
        } else {
            let text = NSAttributedString(
                string: title, attributes: [.font: font!, .foregroundColor: foreground])
            let size = text.size()
            text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
        }
        // The general stroke adds 2 pt; swatches have their own 3.5 pt offset.
        focusStroke.update(
            in: self, rect: isSwatch ? rect.insetBy(dx: -1.5, dy: -1.5) : rect,
            radius: isSwatch ? 9.5 : 9, visible: focused)
    }
    override func keyDown(with event: NSEvent) {
        if case .swatch = style, [123, 124].contains(event.keyCode), let model {
            model.cycleLook(event.keyCode == 123 ? -1 : 1)
            if let root = window?.contentView {
                func find(_ view: NSView) -> NSView? {
                    if view.identifier?.rawValue == "ps.look-\(model.recipe.look.rawValue)" { return view }
                    return view.subviews.lazy.compactMap(find).first
                }
                if let next = find(root) { window?.makeFirstResponder(next) }
            }
            model.onKeyLoopChange?()
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor enum PanelKeyLoop {
    static let order =
        ["preview", "inspect", "remove"] + LookID.allCases.map { "look-\($0.rawValue)" }
        + [
            "adjust", "save", "copy", "shape", "space", "corners", "shadow", "gradient-start", "gradient-end",
            "randomize", "reset",
        ]
    static func configure(root: NSView, window: NSWindow) -> [String] {
        var views: [String: NSView] = [:]
        func visit(_ view: NSView) {
            if let id = view.identifier?.rawValue, id.hasPrefix("ps."), view.canBecomeKeyView {
                views[String(id.dropFirst(3))] = view
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        let keys = order.filter { views[$0] != nil }
        for (index, id) in keys.enumerated() {
            views[id]?.nextKeyView = views[keys[(index + 1) % keys.count]]
        }
        window.autorecalculatesKeyViewLoop = keys.isEmpty
        return keys
    }
}
