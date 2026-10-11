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
            HStack {
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PanelTheme.informationStyle).accessibilityHidden(true)
            }
            Spacer(minLength: 12)
            Image(systemName: "rectangle.inset.filled")
                .font(.system(size: 36, weight: .light)).accessibilityHidden(true)
            Text("Welcome to PremiumShot").font(.system(size: 22, weight: .semibold)).padding(.top, 16)
            Text("PremiumShot lives in your menu bar.").padding(.top, 12)
            Text("Copy a screenshot, press ⌘⌥⇧Space, press Return.")
                .padding(.top, 6).accessibilityLabel("Copy a screenshot, press Command Option Shift Space, then Return.")
            Text("It reads your screenshots folder only when you choose Open latest screenshot. macOS will ask you then.")
                .foregroundStyle(PanelTheme.informationStyle).multilineTextAlignment(.center)
                .frame(maxWidth: 420).padding(.top, 14)
            if model.hotkeyUnavailable {
                Text("The shortcut is unavailable. Use Show Panel in the menu bar.")
                    .foregroundStyle(PanelTheme.informationStyle).padding(.top, 10)
            }
            Spacer(minLength: 12)
            Toggle("Open at login", isOn: Binding(
                get: { model.loginItems.isRequested }, set: { model.loginItems.setEnabled($0) }))
                .toggleStyle(.checkbox).fixedSize()
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
