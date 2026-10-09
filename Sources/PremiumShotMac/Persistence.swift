import Foundation
import PremiumShotCore
import Synchronization

/// The last-used recipe, kept in user defaults and restored on the next summon.
public enum RecipePersistence {
    static let key = "lastRecipe.v1"
    private static let loggedCorruption = Mutex(false)

    public static func load(from defaults: UserDefaults = .standard) -> Recipe {
        guard let data = defaults.data(forKey: key) else { return .default }
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            let shouldLog = loggedCorruption.withLock { logged in
                guard !logged else { return false }
                logged = true
                return true
            }
            if shouldLog { NSLog("PremiumShot: saved style was unreadable; using defaults.") }
            return .default
        }
        return Recipe.decodeLenient(data)  // clamps, replaces unknown ids, ignores newer versions
    }

    public static func save(_ recipe: Recipe, to defaults: UserDefaults = .standard) {
        if let data = try? recipe.encoded() { defaults.set(data, forKey: key) }
    }
}

/// Hidden preferences (no settings window in v1).
public enum Preferences {
    /// "light" (default) or "standard": panel elevation only; transitions share one timing.
    public static func panelWeight(_ defaults: UserDefaults = .standard) -> PanelWeight {
        PanelWeight(rawValue: defaults.string(forKey: "panelWeight") ?? "") ?? .light
    }
}

public enum PanelWeight: String, Sendable { case light, standard }
