import AppKit
import Observation
import ServiceManagement
import SwiftUI

public enum FirstLaunch {
    public static func needsWelcome(in defaults: UserDefaults) -> Bool {
        !defaults.bool(forKey: "firstRunCompleted")
    }

    public static func complete(in defaults: UserDefaults) {
        defaults.set(true, forKey: "firstRunCompleted")
    }
}

/// Read the system's state rather than keeping a second launch-at-login preference.
@MainActor @Observable
public final class LoginItemController {
    public enum State: Equatable { case off, on, needsApproval, unavailable }
    public private(set) var state: State = .off
    public private(set) var message: String?
    @ObservationIgnored private let readStatus: () -> State
    @ObservationIgnored private let register: () throws -> Void
    @ObservationIgnored private let unregister: () throws -> Void

    public convenience init() {
        self.init(
            status: {
                switch SMAppService.mainApp.status {
                case .notRegistered: .off
                case .enabled: .on
                case .requiresApproval: .needsApproval
                case .notFound: .unavailable
                @unknown default: .unavailable
                }
            },
            register: { try SMAppService.mainApp.register() },
            unregister: { try SMAppService.mainApp.unregister() })
    }

    init(status: @escaping () -> State, register: @escaping () throws -> Void,
         unregister: @escaping () throws -> Void) {
        readStatus = status
        self.register = register
        self.unregister = unregister
        refresh()
    }

    public var isRequested: Bool { state == .on || state == .needsApproval }

    public func refresh() {
        state = readStatus()
        if state == .needsApproval {
            message = "Allow PremiumShot in System Settings → General → Login Items."
        } else {
            message = nil
        }
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isRequested else { return }
        do {
            try enabled ? register() : unregister()
            refresh()
        } catch {
            state = readStatus()
            message = "Couldn't change Open at Login. Try again in System Settings."
        }
    }

    public func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

struct WelcomeView: View {
    let model: PanelModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().scaledToFit().frame(width: 64, height: 64).accessibilityHidden(true)
            Text("Welcome to PremiumShot").font(.system(size: 22, weight: .semibold)).padding(.top, 16)
            Text("PremiumShot lives in your menu bar.").padding(.top, 12)
            HStack(spacing: 6) {
                Text("Copy a screenshot, press")
                ShortcutKeycap(label: "⌘⌥⇧Space")
                Text("then")
                ShortcutKeycap(label: "Return ↵")
            }
            .padding(.top, 10).accessibilityElement(children: .ignore)
            .accessibilityLabel("Copy a screenshot, press Command Option Shift Space, then Return.")
            Text("It reads your screenshots folder only when you choose Open latest screenshot. macOS will ask you then.")
                .foregroundStyle(PanelTheme.informationStyle).multilineTextAlignment(.center)
                .frame(maxWidth: 420).padding(.top, 14)
            if model.hotkeyUnavailable {
                Text("The shortcut is unavailable. Use Show Panel in the menu bar.")
                    .foregroundStyle(PanelTheme.informationStyle).padding(.top, 10)
            }
            Spacer(minLength: 12)
            WelcomeLoginToggle(model: model).frame(width: 118, height: 24)
            if let message = model.loginItems.message {
                Button(message) { model.loginItems.openSettings() }
                    .buttonStyle(.link).font(.system(size: 11)).padding(.top, 5)
            }
            PanelAction(model: model, title: "Start", id: "welcome-start", style: .primary,
                        keyEquivalent: "\r") { model.finishWelcome() }
                .frame(width: 100, height: 38).padding(.top, 14)
            Spacer(minLength: 16)
        }
        .padding(24).frame(width: PanelMetrics.card.width, height: PanelMetrics.card.height)
        .font(.system(size: 13))
    }
}

private struct ShortcutKeycap: View {
    let label: String
    var body: some View {
        Text(label).font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.22), lineWidth: 1))
    }
}

/// Native checkbox semantics with an opaque outline that stays visible over material.
private struct WelcomeLoginToggle: NSViewRepresentable {
    let model: PanelModel
    func makeNSView(context: Context) -> WelcomeLoginButton {
        WelcomeLoginButton(model: model)
    }
    func updateNSView(_ button: WelcomeLoginButton, context: Context) {
        button.state = model.loginItems.isRequested ? .on : .off
        button.setAccessibilityValue(button.state == .on ? 1 : 0)
        button.needsDisplay = true
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WelcomeLoginButton, context: Context) -> CGSize? {
        CGSize(width: 118, height: 24)
    }
}

private final class WelcomeLoginButton: NSButton {
    let model: PanelModel
    private let focusStroke = NativeFocusStroke()
    init(model: PanelModel) {
        self.model = model
        super.init(frame: .zero)
        title = "Open at login"
        setButtonType(.switch)
        isBordered = false
        focusRingType = .none
        target = self
        action = #selector(toggled)
        identifier = NSUserInterfaceItemIdentifier("ps.welcome-login")
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 118, height: 24) }
    override var allowsVibrancy: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
    override func becomeFirstResponder() -> Bool {
        model.focus = .control
        needsDisplay = true
        return true
    }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    @objc private func toggled() {
        model.loginItems.setEnabled(state == .on)
        state = model.loginItems.isRequested ? .on : .off
        setAccessibilityValue(state == .on ? 1 : 0)
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: 2.5, y: (bounds.height - 14) / 2, width: 14, height: 14)
        let box = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        if state == .on {
            NSColor.labelColor.setFill(); box.fill()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: rect.minX + 3, y: rect.minY + 7))
            tick.line(to: NSPoint(x: rect.minX + 6, y: rect.minY + 4))
            tick.line(to: NSPoint(x: rect.minX + 11, y: rect.minY + 10))
            tick.lineWidth = 1.5; tick.lineCapStyle = .round; tick.lineJoinStyle = .round
            NSColor.windowBackgroundColor.setStroke(); tick.stroke()
        } else {
            PanelTheme.information.setStroke(); box.lineWidth = 1.25; box.stroke()
        }
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        text.draw(at: NSPoint(x: 24, y: (bounds.height - text.size().height) / 2))
        focusStroke.update(in: self, rect: bounds.insetBy(dx: 2, dy: 2), radius: 4,
                           visible: model.keyboardFocus && window?.firstResponder === self)
    }
}
