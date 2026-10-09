import AppKit
import SwiftUI

enum WellTone: String, CaseIterable { case current, lightHairline, recessed }

enum PanelTheme {
    static let wellTone: WellTone = .recessed
    /// Opaque informational ink avoids double-dimming through the desktop material.
    static let information = NSColor(name: "PremiumShot information") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 0.79, green: 0.80, blue: 0.82, alpha: 1)
            : NSColor(srgbRed: 0.32, green: 0.33, blue: 0.35, alpha: 1)
    }
    static var informationStyle: Color { Color(nsColor: information) }
}

struct WellSurface: View {
    var tone: WellTone = PanelTheme.wellTone
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(fill(dark: dark))
            .overlay {
                if tone == .lightHairline {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                }
            }
    }
    private func fill(dark: Bool) -> Color {
        switch tone {
        case .current: Color.primary.opacity(0.055)
        case .lightHairline: dark ? Color.white.opacity(0.085) : Color.white.opacity(0.24)
        case .recessed: Color.black.opacity(dark ? 0.14 : 0.09)
        }
    }
}
