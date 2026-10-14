import PremiumShotCore
import SwiftUI

public enum PanelMetrics {
    public static let card = CGSize(width: 600, height: 412)
    public static let cornerRadius: CGFloat = 22
    public static let well = CGSize(width: 576, height: 328)
}

struct PanelView: View {
    let model: PanelModel
    var presentation: PanelPresentation? = nil
    var wellTone: WellTone = PanelTheme.wellTone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    var body: some View {
        let _ = model.copySequence
        Group {
            if model.isWelcoming {
                WelcomeView(model: model)
            } else if let presentation {
                ZStack(alignment: .topLeading) {
                    editor.opacity(presentation.compactOpacity)
                        .allowsHitTesting(!model.isInspecting)
                        .accessibilityHidden(model.isInspecting)
                    if presentation.showInspect {
                        InspectView(
                            model: model, targetSize: presentation.inspectSize,
                            presentation: presentation, wellTone: wellTone
                        )
                        .frame(width: presentation.inspectSize.width, height: presentation.inspectSize.height)
                        .opacity(presentation.inspectOpacity)
                        .allowsHitTesting(presentation.showInspect)
                        .accessibilityHidden(!model.isInspecting)
                    }
                }
            } else if model.isInspecting {
                InspectView(model: model, wellTone: wellTone)
            } else {
                editor
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(
                Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .font(.system(size: 13))
    }
    private var editor: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                well.frame(width: 576, height: 328)
                caption.frame(height: 24)
                bar.frame(maxHeight: .infinity)
            }.padding(.horizontal, 12).padding(.top, 12).frame(width: 600, height: 412)
            if presentation?.showDrawer ?? model.isExpanded {
                AdjustView(model: model).opacity(presentation?.drawerOpacity ?? 1)
                    .disabled(!model.isReady)
                    .allowsHitTesting(model.isExpanded)
                    .accessibilityHidden(!model.isExpanded)
            }
        }.fixedSize(horizontal: true, vertical: true)
    }
    private var well: some View {
        ZStack {
            WellSurface(tone: wellTone)
            if model.isImporting && !model.isReady {
                if model.progressVisible { ProgressView().controlSize(.small) }
            } else if model.phase == .ready {
                PreviewSurface(model: model)
                    .opacity(presentation?.sharedImage == true ? 0 : 1)
                if model.progressVisible { ProgressView().controlSize(.small) }
                if hovering || model.focus != .panel {
                    VStack {
                        ZStack(alignment: .topLeading) {
                            HStack {
                                Spacer()
                                pill(
                                    "arrow.up.left.and.arrow.down.right", name: "Inspect screenshot",
                                    help: "Inspect screenshot (Space)"
                                ) { model.toggleInspect() }
                            }
                            pill("trash", name: "Remove screenshot", help: "Remove screenshot (⌫)") {
                                model.removeScreenshot()
                            }
                        }
                        Spacer()
                    }.padding(10)

                }
            } else {
                empty
            }
            if let image = model.removalThumbnail {
                RemovalGhost(image: image).padding(.horizontal, 16).padding(.vertical, 14)
            }
            if model.dropTarget {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: 2).background(
                    Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14)
                ).allowsHitTesting(false)
                Text(model.isReady ? "Drop to replace" : "Drop to import")
                    .font(.system(size: 13, weight: .medium)).padding(10)
                    .background(.regularMaterial, in: Capsule()).allowsHitTesting(false)
            }
        }.onHover { hovering = $0 }
    }
    private var empty: some View {
        VStack(spacing: 7) {
            Image(systemName: "photo").font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
            if model.phase == .alreadyPolished {
                Text("The clipboard holds an image you already polished.")
                    .font(.system(size: 16, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text("Paste or drop the original.").foregroundStyle(.secondary)
                Button("Use it anyway") { model.useAlreadyPolishedAnyway() }.panelFocus(model: model)
            } else {
                Text("Drop a screenshot").font(.system(size: 16, weight: .semibold))
                if case .empty(let reason) = model.phase {
                    Text(reason ?? "or paste the image on your clipboard").foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 460)
                }
                HStack(spacing: 12) {
                    Button("Paste ⌘V") { model.paste() }.panelFocus(model: model)
                    Button("Open latest screenshot…") { model.openLatest() }.panelFocus(model: model)
                }.padding(.top, 8)
                if model.needsScreenshotFolder {
                    HStack(spacing: 12) {
                        Button("Open Privacy Settings") { model.openScreenshotPrivacySettings() }
                            .panelFocus(model: model)
                        Button("Choose a folder…") { model.chooseScreenshotFolder() }
                            .panelFocus(model: model)
                    }.padding(.top, 6)
                }
            }
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 11).strokeBorder(
                    Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                ).padding(14).allowsHitTesting(false))
    }
    private func pill(_ symbol: String, name: String, help: String, action: @escaping () -> Void) -> some View
    {
        PanelAction(
            model: model, title: name, symbol: symbol,
            id: symbol == "trash" ? "remove" : "inspect", style: .icon, action: action
        )
        .frame(width: 28, height: 28).help(help)
    }

    private var caption: some View {
        HStack(spacing: 5) {
            Text(captionText).foregroundStyle(isError ? Color.red : PanelTheme.informationStyle).lineLimit(1)
            if model.needsSaveFolder {
                Button("Choose folder…") {
                    model.focus = .control
                    model.chooseSaveFolder()
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 4)
            if let l = model.layout {
                Text(
                    hovering || (model.focus == .preview && model.keyboardFocus)
                        ? "Drag out · Space to inspect"
                        : "Screenshot at \(Int((l.screenshotScale*100).rounded()))% of original size"
                )
                .foregroundStyle(PanelTheme.informationStyle).lineLimit(1)
                .contentTransition(.opacity)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.12),
                    value: hovering || (model.focus == .preview && model.keyboardFocus)
                )
                .help("The screenshot is never enlarged beyond its original pixels.")
            }
        }.font(.system(size: 11.5)).monospacedDigit().padding(.horizontal, 6)
    }
    private var captionText: String {
        if model.isImporting { return "Receiving…" }
        if let status = model.status {
            switch status {
            case .copied(let text), .saved(let text), .notice(let text), .error(let text): return text
            }
        }
        guard let l = model.layout else { return "" }
        return "\(l.width.formatted()) × \(l.height.formatted()) px" + (l.capped ? " · capped" : "")
    }
    private var isError: Bool { if case .error? = model.status { true } else { false } }
    private var copied: Bool { if case .copied? = model.status { true } else { false } }
    private var saved: Bool { if case .saved? = model.status { true } else { false } }
    private var bar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(LookID.allCases, id: \.self) { id in
                    PanelAction(
                        model: model, title: Look.look(id).name, id: "look-\(id.rawValue)",
                        style: .swatch(id), selected: model.recipe.look == id
                    ) {
                        model.focus = .look
                        model.edit { $0.look = id }
                    }.frame(width: 38, height: 32).disabled(!model.isReady)
                }
            }
            Text(Look.look(model.recipe.look).name).font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(PanelTheme.informationStyle).frame(width: 62, alignment: .leading)
            Spacer(minLength: 0)
            PanelAction(model: model, title: "Adjust", id: "adjust", selected: model.isExpanded) {
                model.toggleDrawer()
            }.frame(width: 64, height: 38).disabled(!model.isReady || !model.canExpand)
            PanelAction(model: model, title: saved ? "Saved" : "Save", id: "save") {
                Task { await model.save() }
            }.frame(width: 54, height: 38).disabled(!model.isReady)
            PanelAction(model: model, title: copied ? "✓ Copied" : "Copy  ↵", id: "copy", style: .primary) {
                Task { await model.copy() }
            }.frame(width: 106, height: 38).disabled(!model.isReady)
        }
    }

}

private struct RemovalGhost: View {
    let image: CGImage
    @State private var leaving = false
    var body: some View {
        Image(decorative: image, scale: 1).resizable().scaledToFit()
            .scaleEffect(leaving ? 0.97 : 1).opacity(leaving ? 0 : 1)
            .allowsHitTesting(false).accessibilityHidden(true)
            .onAppear { withAnimation(.easeOut(duration: 0.15)) { leaving = true } }
    }
}
