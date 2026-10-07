import Foundation
import PremiumShotCore

/// The last-used recipe, kept in user defaults and restored on the next summon.
public enum RecipePersistence {
    static let key = "lastRecipe.v1"

    public static func load(from defaults: UserDefaults = .standard) -> Recipe {
        guard let data = defaults.data(forKey: key) else { return .default }
        return Recipe.decodeLenient(data)   // clamps, replaces unknown ids, ignores newer versions
    }

    public static func save(_ recipe: Recipe, to defaults: UserDefaults = .standard) {
        if let data = try? recipe.encoded() { defaults.set(data, forKey: key) }
    }
}

/// Hidden preferences (no settings window in v1).
public enum Preferences {
    /// "light" (default) or "standard": which panel elevation and motion weight to use.
    public static func panelWeight(_ defaults: UserDefaults = .standard) -> PanelWeight {
        PanelWeight(rawValue: defaults.string(forKey: "panelWeight") ?? "") ?? .light
    }
}

public enum PanelWeight: String, Sendable { case light, standard }
