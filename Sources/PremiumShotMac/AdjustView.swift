import AppKit
import PremiumShotCore
import SwiftUI

struct AdjustView: View {
    let model: PanelModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                label("Shape")
                RadioControl(
                    model: model, labels: ["Fit", "16:9", "4:5", "1:1", "1.91:1"],
                    selection: Shape.allCases.firstIndex(of: model.recipe.shape)!, name: "Shape"
                ) { index in model.edit { $0.shape = Shape.allCases[index] } }
                Text(shapeHint).font(.system(size: 11.5)).foregroundStyle(PanelTheme.informationStyle).frame(
                    height: 28, alignment: .topLeading)
            }
            slider("Space", keyPath: \.space)
            slider("Corners", keyPath: \.radius)
            slider("Shadow", keyPath: \.shadow)
            VStack(alignment: .leading, spacing: 7) {
                label("Gradient")
                HStack(spacing: 8) {
                    HueStrip(model: model).frame(width: 168, height: 32)
                    PanelAction(
                        model: model, title: "Randomize", symbol: "dice.fill", id: "randomize",
                        style: .roundIcon
                    ) {
                        model.randomizeGradient()
                    }.frame(width: 32, height: 32)
                }
            }
            Spacer(minLength: 0)
            HStack {
                PanelAction(model: model, title: "Reset look", id: "reset") { model.resetLook() }
                    .frame(width: 64, height: 24)
                Spacer()
                Text("⌘Z undo").foregroundStyle(PanelTheme.informationStyle)
            }.font(.system(size: 11.5))
        }.padding(16).frame(width: 244, height: 412).background(Color.primary.opacity(0.015))
            .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 0.5) }
    }
    private func label(_ title: String) -> some View {
        Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(PanelTheme.informationStyle)
    }
    private func slider(_ title: String, keyPath: WritableKeyPath<Recipe, Int>) -> some View {
        VStack(spacing: 7) {
            HStack {
                label(title)
                Spacer()
                Text("\(model.recipe[keyPath:keyPath])").font(.system(size: 11.5)).monospacedDigit()
                    .foregroundStyle(PanelTheme.informationStyle)
            }
            SliderControl(
                model: model, value: model.recipe[keyPath: keyPath], name: title,
                onEditing: { editing in
                    model.focus = .control
                    editing ? model.beginSlider() : model.endSlider()
                }
            ) { value in model.edit { $0[keyPath: keyPath] = value } }
        }
    }
    private var shapeHint: String {
        switch model.recipe.shape {
        case .fit: "The screenshot’s own shape"
        case .wide: "Slides, X posts, video"
        case .portrait: "Portrait feed posts"
        case .square: "Square posts"
        case .link: "Link previews: Open Graph, LinkedIn"
        }
    }
}

struct RadioControl: NSViewRepresentable {
    let model: PanelModel
    let labels: [String], selection: Int, name: String
    let change: (Int) -> Void
    func makeNSView(context: Context) -> Radio {
        let view = Radio(labels: labels, trackingMode: .selectOne, target: nil, action: nil)
        view.model = model
        view.focusRingType = .none
        view.segmentStyle = .rounded
        view.segmentDistribution = .fillEqually
        view.font = .systemFont(ofSize: 11.5)
        view.controlSize = .small
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.target = view
        view.action = #selector(Radio.changed)
        view.setAccessibilityLabel(name)
        view.identifier = NSUserInterfaceItemIdentifier("ps.\(name.lowercased())")
        return view
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Radio, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.intrinsicContentSize.width,
            height: nsView.intrinsicContentSize.height)
    }
    func updateNSView(_ view: Radio, context: Context) {
        view.isEnabled = context.environment.isEnabled
        view.selectedSegment = selection
        view.needsDisplay = true
        view.change = change
        model.onKeyLoopChange?()
    }
    final class Radio: NSSegmentedControl {
        weak var model: PanelModel?
        private let focusStroke = NativeFocusStroke()
        override var acceptsFirstResponder: Bool { isEnabled }
        override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }
        override func becomeFirstResponder() -> Bool {
            model?.focus = .control
            needsDisplay = true
            return super.becomeFirstResponder()
        }
        override func resignFirstResponder() -> Bool {
            needsDisplay = true
            return super.resignFirstResponder()
        }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
            let width = bounds.width / CGFloat(max(1, segmentCount))
            for index in 0..<segmentCount {
                let selected = index == selectedSegment
                let cell = NSRect(
                    x: bounds.minX + CGFloat(index) * width,
                    y: bounds.minY, width: width, height: bounds.height)
                if selected {
                    NSColor.labelColor.setFill()
                    NSBezierPath(roundedRect: cell, xRadius: 6, yRadius: 6).fill()
                }
                let text = NSAttributedString(
                    string: label(forSegment: index) ?? "",
                    attributes: [
                        .font: font ?? .systemFont(ofSize: 11.5),
                        .foregroundColor: selected ? NSColor.windowBackgroundColor : PanelTheme.information,
                    ])
                text.draw(
                    at: NSPoint(
                        x: cell.midX - text.size().width / 2,
                        y: cell.midY - text.size().height / 2))
            }
            let rect = NSRect(
                x: bounds.minX + CGFloat(max(0, selectedSegment)) * width,
                y: bounds.minY + 1, width: width, height: bounds.height - 2)
            focusStroke.update(
                in: self, rect: rect, radius: 7,
                visible: isEnabled && model?.keyboardFocus == true && window?.firstResponder === self)
        }
        var change: ((Int) -> Void)?
        @objc func changed() { change?(selectedSegment) }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 123 || event.keyCode == 124 {
                selectedSegment =
                    (selectedSegment + (event.keyCode == 123 ? -1 : 1) + segmentCount) % segmentCount
                changed()
                return
            }
            super.keyDown(with: event)
        }
    }
}

struct SliderControl: NSViewRepresentable {
    let model: PanelModel
    let value: Int, name: String
    let onEditing: (Bool) -> Void, change: (Int) -> Void
    func makeNSView(context: Context) -> Control {
        let view = Control(value: Double(value), minValue: 0, maxValue: 100, target: nil, action: nil)
        view.model = model
        view.focusRingType = .none
        view.target = view
        view.action = #selector(Control.changed)
        view.isContinuous = true
        view.controlSize = .small
        view.setAccessibilityLabel(name)
        view.identifier = NSUserInterfaceItemIdentifier("ps.\(name.lowercased())")
        return view
    }
    func updateNSView(_ view: Control, context: Context) {
        view.isEnabled = context.environment.isEnabled
        view.doubleValue = Double(value)
        view.needsDisplay = true
        view.change = change
        view.onEditing = onEditing
        model.onKeyLoopChange?()
    }
    final class Control: NSSlider {
        weak var model: PanelModel?
        private let focusStroke = NativeFocusStroke()
        override var acceptsFirstResponder: Bool { isEnabled }
        override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
        override func becomeFirstResponder() -> Bool {
            model?.focus = .control
            needsDisplay = true
            return super.becomeFirstResponder()
        }
        override func resignFirstResponder() -> Bool {
            needsDisplay = true
            return super.resignFirstResponder()
        }
        override func draw(_ dirtyRect: NSRect) {
            // Keep NSSlider's hit testing, tracking and accessibility; only its ink is neutral.
            let track = NSRect(x: 6, y: bounds.midY - 2, width: max(0, bounds.width - 12), height: 4)
            NSColor.labelColor.withAlphaComponent(0.13).setFill()
            NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
            let rect = (cell as? NSSliderCell)?.knobRect(flipped: isFlipped) ?? .zero
            let fill = NSRect(
                x: track.minX, y: track.minY,
                width: max(0, rect.midX - track.minX), height: track.height)
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: fill, xRadius: 2, yRadius: 2).fill()
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowColor = .black.withAlphaComponent(0.2)
            shadow.set()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.labelColor.withAlphaComponent(0.18).setStroke()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.25, dy: 0.25)).stroke()
            focusStroke.update(
                in: self, rect: rect, radius: nil,
                visible: isEnabled && model?.keyboardFocus == true && window?.firstResponder === self)
        }
        var change: ((Int) -> Void)?, onEditing: ((Bool) -> Void)?
        @objc func changed() { change?(Int(doubleValue.rounded())) }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            onEditing?(true)
            super.mouseDown(with: event)
            onEditing?(false)
        }
        override func keyDown(with event: NSEvent) {
            if [123, 124, 125, 126].contains(event.keyCode) {
                onEditing?(true)
                let delta = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
                doubleValue = min(
                    100, max(0, doubleValue + ([124, 126].contains(event.keyCode) ? delta : -delta)))
                changed()
                onEditing?(false)
                return
            }
            super.keyDown(with: event)
        }
    }
}

/// A layer can draw outside a small native control's bounds without clipping its focus outline.
@MainActor final class NativeFocusStroke {
    private let stroke = CAShapeLayer()
    private var showing = false
    init() { stroke.opacity = 0 }
    func update(in view: NSView, rect: NSRect, radius: CGFloat?, visible: Bool) {
        view.wantsLayer = true
        if stroke.superlayer == nil { view.layer?.addSublayer(stroke) }
        let show = visible && !rect.isEmpty
        let oldOpacity = stroke.presentation()?.opacity ?? stroke.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stroke.frame = view.bounds
        stroke.isHidden = rect.isEmpty
        stroke.opacity = show ? 1 : 0
        stroke.strokeColor = NSColor.labelColor.cgColor
        stroke.fillColor = NSColor.clear.cgColor
        stroke.lineWidth = 2
        let expanded = rect.insetBy(dx: -2, dy: -2)
        if let radius {
            stroke.path = CGPath(
                roundedRect: expanded, cornerWidth: radius + 2, cornerHeight: radius + 2, transform: nil)
        } else {
            stroke.path = CGPath(ellipseIn: expanded, transform: nil)
        }
        CATransaction.commit()
        if show != showing && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = oldOpacity
            fade.toValue = show ? 1 : 0
            fade.duration = 0.12
            stroke.add(fade, forKey: "focusFade")
        }
        showing = show
    }
}
