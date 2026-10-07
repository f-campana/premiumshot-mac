import AppKit
import Observation
import PremiumShotCore

/// Everything the panel shows, and the actions it can take. M0 shows a static preview and a working Copy;
/// the controls arrive in M1.
@MainActor @Observable
public final class PanelModel {
    public enum Phase: Equatable { case empty(String?), alreadyPolished, ready }
    public enum Status: Equatable { case copied(String), error(String) }

    public private(set) var phase: Phase = .empty(nil)
    public private(set) var preview: CGImage?
    public private(set) var layout: Layout?
    public private(set) var status: Status?
    public private(set) var isCopying = false
    public private(set) var previewGeneration = 0

    public var recipe: Recipe = .default
    public var backingScale: CGFloat = 2
    /// Overrides the clipboard with a file, for dev runs (`--image`).
    public var demoImageURL: URL?

    /// Injected so tests can use a private pasteboard and force write failures.
    public var pasteboard: NSPasteboard = .general
    public var pasteboardWriter: (Data, UUID, (width: Int, height: Int), NSPasteboard) -> Bool = {
        PasteboardIO.writePNG($0, marker: $1, expectedSize: $2, to: $3)
    }
    public var defaults: UserDefaults = .standard

    let store: SessionStore
    private let queue = RenderQueue()
    private var session: SourceSession?
    private var pendingPolished: SourceImage?
    private var statusToken = 0

    public init(store: SessionStore) { self.store = store }

    /// Preview well geometry in points (spec: 576 × 328 well, 544 × 300 canvas box).
    public static let canvasBox = CGSize(width: 544, height: 300)

    // MARK: Summon

    public func summon() {
        setStatus(nil)
        recipe = RecipePersistence.load(from: defaults)
        let resolved: SummonSource
        if let url = demoImageURL, let image = try? ImageLoader.load(url: url) { resolved = .image(image) }
        else { resolved = SummonSource.resolve(pasteboard: pasteboard, store: store) }

        switch resolved {
        case .session(let s): begin(s)
        case .image(let image): begin(store.add(source: image, recipe: recipe))
        case .alreadyPolished(let image):
            pendingPolished = image; session = nil; preview = nil; layout = nil; phase = .alreadyPolished
        case .empty(let reason):
            session = nil; preview = nil; layout = nil; phase = .empty(reason)
        }
    }

    /// "Use it anyway": treat the already-polished clipboard image as a normal source.
    public func useAlreadyPolishedAnyway() {
        guard let image = pendingPolished else { return }
        pendingPolished = nil
        begin(store.add(source: image, recipe: recipe))
    }

    private func begin(_ s: SourceSession) {
        session = s; recipe = s.recipe; phase = .ready
        layout = LayoutEngine.resolve(sourceWidth: s.source.width, sourceHeight: s.source.height, recipe: s.recipe)
        renderPreview()
    }

    // MARK: Preview

    public func renderPreview() {
        guard let session else { return }
        let source = session.source, recipe = session.recipe, scale = backingScale
        let resolved = LayoutEngine.resolve(sourceWidth: source.width, sourceHeight: source.height, recipe: recipe)
        layout = resolved
        let aspect = Double(resolved.width) / Double(resolved.height)
        let heightPoints = min(Self.canvasBox.height, Self.canvasBox.width / aspect)
        let heightPixels = max(8, Int((heightPoints * scale).rounded()))
        let id = session.id
        Task { [queue] in
            guard let result = try? await queue.preview(source: source, recipe: recipe, height: heightPixels) else { return }
            await MainActor.run {
                guard self.session?.id == id else { return }
                self.preview = result.image; self.previewGeneration += 1
            }
        }
    }

    // MARK: Copy

    /// Copies the full-size render. Success is reported **only after** the pasteboard accepted the PNG and it
    /// read back at the resolved size.
    public func copy() async {
        guard let session, !isCopying else { return }
        isCopying = true; defer { isCopying = false }
        do {
            let result = try await queue.export(source: session.source, recipe: session.recipe)
            let data = try PNG.encode(result.image)
            let size = (width: result.layout.width, height: result.layout.height)
            guard pasteboardWriter(data, session.id, size, pasteboard) else {
                setStatus(.error("Couldn't copy to the clipboard.")); return
            }
            RecipePersistence.save(session.recipe, to: defaults)
            setStatus(.copied("Copied \(size.width) × \(size.height) px"))
        } catch {
            setStatus(.error(error.localizedDescription))
        }
    }

    private func setStatus(_ new: Status?) {
        status = new; statusToken += 1
        guard new != nil else { return }
        let token = statusToken
        Task { try? await Task.sleep(for: .seconds(1.7)); if token == statusToken { status = nil } }
    }

    public var currentSession: SourceSession? { session }
}
