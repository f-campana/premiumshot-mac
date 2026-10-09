import SwiftUI

private struct PanelFocus: ViewModifier {
    let model: PanelModel
    var radius: CGFloat
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduced
    func body(content: Content) -> some View {
        content.focusable(enabled).focused($focused).focusEffectDisabled()
            .overlay {
                RoundedRectangle(cornerRadius: radius + 2)
                    .stroke(Color.primary, lineWidth: 2).padding(-2)
                    .opacity(focused && enabled && model.keyboardFocus ? 1 : 0)
                    .allowsHitTesting(false)
                    .animation(
                        reduced ? nil : .easeOut(duration: 0.12), value: focused && model.keyboardFocus)
            }
            .onChange(of: focused) { _, value in if value { model.focus = .control } }
    }
}

extension View {
    func panelFocus(model: PanelModel, radius: CGFloat = 9) -> some View {
        modifier(PanelFocus(model: model, radius: radius))
    }
}
