import PremiumShotCore
import SwiftUI

public enum PanelMetrics {
    public static let card = CGSize(width: 600, height: 412)
    public static let cornerRadius: CGFloat = 22
    public static let well = CGSize(width: 576, height: 328)
}

/// M0 panel content: preview well, caption line, and a bar with the look name and Copy.
struct PanelView: View {
    let model: PanelModel

    var body: some View {
        VStack(spacing: 0) {
            well.frame(width: PanelMetrics.well.width, height: PanelMetrics.well.height)
            captionRow.frame(height: 24)
            barRow.frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 12).padding(.top, 12)
        .frame(width: PanelMetrics.card.width, height: PanelMetrics.card.height)
        .overlay(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        .font(.system(size: 13))
    }

    private var well: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.055))
            switch model.phase {
            case .ready:
                if let preview = model.preview {
                    Image(decorative: preview, scale: model.backingScale)
                        .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                } else { ProgressView().controlSize(.small) }
            case .empty(let reason):
                VStack(spacing: 6) {
                    Image(systemName: "photo").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                    Text("Drop a screenshot").font(.system(size: 16, weight: .semibold))
                    Text(reason ?? "or paste the image on your clipboard").foregroundStyle(.secondary)
                }
            case .alreadyPolished:
                VStack(spacing: 8) {
                    Text("The clipboard holds an image you already polished").font(.system(size: 15, weight: .semibold))
                    Text("Paste or drop the original.").foregroundStyle(.secondary)
                    Button("Use it anyway") { model.useAlreadyPolishedAnyway() }
                }
            }
        }
    }

    private var captionRow: some View {
        HStack {
            switch model.status {
            case .copied(let text)?: Text(text)
            case .error(let text)?: Text(text).foregroundStyle(.red)
            case nil: Text(sizeText)
            }
            Spacer()
            if let layout = model.layout { Text("Screenshot at \(Int((layout.screenshotScale * 100).rounded()))% of original size") }
        }
        .font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit().padding(.horizontal, 6)
    }

    private var sizeText: String {
        guard let l = model.layout else { return "" }
        return "\(l.width.formatted()) × \(l.height.formatted()) px" + (l.capped ? " · capped" : "")
    }

    private var barRow: some View {
        HStack {
            Text(Look.look(model.recipe.look).name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary).padding(.leading, 4)
            Spacer()
            Button { Task { await model.copy() } } label: {
                HStack(spacing: 6) {
                    if case .copied? = model.status { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                    Text(isCopied ? "Copied" : "Copy")
                    Text("⏎").opacity(0.5)
                }
                .font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).frame(minWidth: 100, minHeight: 32)
                .foregroundStyle(Color(nsColor: .windowBackgroundColor)).background(Color.primary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain).disabled(model.phase != .ready)
        }
    }

    private var isCopied: Bool { if case .copied? = model.status { true } else { false } }
}
