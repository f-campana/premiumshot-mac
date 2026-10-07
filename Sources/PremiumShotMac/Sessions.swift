import AppKit
import PremiumShotCore

/// One image being polished: the decoded original and its recipe. Kept in memory only.
public final class SourceSession: Identifiable {
    public let id: UUID
    public let source: SourceImage
    public var recipe: Recipe
    init(id: UUID = UUID(), source: SourceImage, recipe: Recipe) { self.id = id; self.source = source; self.recipe = recipe }
}

/// The last few sessions, so re-summoning after Copy reopens the original instead of polishing the polished image.
@MainActor
public final class SessionStore {
    public static let capacity = 3
    private var sessions: [SourceSession] = []
    public init() {}

    @discardableResult
    public func add(source: SourceImage, recipe: Recipe) -> SourceSession {
        let session = SourceSession(source: source, recipe: recipe)
        sessions.append(session)
        if sessions.count > Self.capacity { sessions.removeFirst(sessions.count - Self.capacity) }
        return session
    }
    public func session(id: UUID) -> SourceSession? { sessions.first { $0.id == id } }
    public var count: Int { sessions.count }
}

/// What the panel should show when summoned.
public enum SummonSource {
    /// The clipboard holds our own earlier output and its session is still in memory.
    case session(SourceSession)
    /// A plain image to polish.
    case image(SourceImage)
    /// The clipboard holds our own output but the session is gone (after a restart). Offer "Use it anyway".
    case alreadyPolished(SourceImage)
    /// Nothing usable: show the empty state, with the reason if there is one.
    case empty(reason: String?)

    @MainActor
    public static func resolve(pasteboard: NSPasteboard = .general, store: SessionStore) -> SummonSource {
        switch PasteboardIO.read(from: pasteboard) {
        case .none(let reason): return .empty(reason: reason)
        case .image(let image, let marker):
            guard let marker else { return .image(image) }
            if let session = store.session(id: marker) { return .session(session) }
            return .alreadyPolished(image)
        }
    }
}
