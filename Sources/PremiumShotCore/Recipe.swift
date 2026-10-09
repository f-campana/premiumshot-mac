import Foundation

public enum LookID: String, Codable, CaseIterable, Sendable {
    case dawn, tide, paper, graphite, clear, custom
}

public enum Shape: String, Codable, CaseIterable, Sendable {
    case fit = "fit"
    case wide = "16:9"
    case portrait = "4:5"
    case square = "1:1"
    case link = "1.91:1"

    /// Fixed canvas size in output pixels, or nil for Fit.
    public var canvas: (width: Double, height: Double)? {
        switch self {
        case .fit: return nil
        case .wide: return (1920, 1080)
        case .portrait: return (1080, 1350)
        case .square: return (1080, 1080)
        case .link: return (1200, 630)
        }
    }
}

/// Reserved for M2 (manual solid redaction). Rectangles are in **source-image pixel coordinates**
/// so they survive any scaling. M1 rejects a non-empty list rather than silently ignoring it.
public struct Redaction: Codable, Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// The whole editable state of one polished image. Versioned so saved recipes survive changes.
public struct Recipe: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var look: LookID
    public var shape: Shape
    public var space: Int
    public var radius: Int
    public var shadow: Int
    public var gradientFrom: Int
    public var gradientTo: Int
    public var redactions: [Redaction]

    public init(
        version: Int = Recipe.currentVersion, look: LookID = .dawn, shape: Shape = .fit,
        space: Int = 50, radius: Int = 50, shadow: Int = 55, gradientFrom: Int = 155, gradientTo: Int = 265,
        redactions: [Redaction] = []
    ) {
        self.version = version
        self.look = look
        self.shape = shape
        self.space = space
        self.radius = radius
        self.shadow = shadow
        self.gradientFrom = gradientFrom
        self.gradientTo = gradientTo
        self.redactions = redactions
    }

    public static let `default` = Recipe()

    private enum CodingKeys: String, CodingKey {
        case version, look, shape, space, radius, shadow, gradientFrom, gradientTo, frame, redactions
    }

    /// Every key is required except `redactions`, so a typo in a recipe file is an error, not a silent default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        guard version == 1 || version == Self.currentVersion else {
            throw PremiumShotError.invalidRecipe(
                "version \(version) is not supported (this build reads versions 1 and 2)")
        }
        look = try c.decode(LookID.self, forKey: .look)
        shape = try c.decode(Shape.self, forKey: .shape)
        space = try c.decode(Int.self, forKey: .space)
        radius = try c.decode(Int.self, forKey: .radius)
        shadow = try c.decode(Int.self, forKey: .shadow)
        if let frame = try c.decodeIfPresent(String.self, forKey: .frame), frame != "none" {
            throw PremiumShotError.invalidRecipe(
                "Frame was removed. Remove the frame field or set it to none.")
        }
        if version == 1 {
            guard look != .custom else {
                throw PremiumShotError.invalidRecipe("unknown or invalid value for \"look\" in version 1")
            }
            gradientFrom = 155
            gradientTo = 265
        } else {
            gradientFrom = try c.decode(Int.self, forKey: .gradientFrom)
            gradientTo = try c.decode(Int.self, forKey: .gradientTo)
        }
        version = Self.currentVersion
        redactions = try c.decodeIfPresent([Redaction].self, forKey: .redactions) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(look, forKey: .look)
        try c.encode(shape, forKey: .shape)
        try c.encode(space, forKey: .space)
        try c.encode(radius, forKey: .radius)
        try c.encode(shadow, forKey: .shadow)
        try c.encode(gradientFrom, forKey: .gradientFrom)
        try c.encode(gradientTo, forKey: .gradientTo)
        try c.encode(redactions, forKey: .redactions)
    }

    // MARK: Validation

    /// Strict check used by the CLI and by tests. Throws `.invalidRecipe` with a one-line reason.
    public func validate() throws {
        guard version == Recipe.currentVersion else {
            throw PremiumShotError.invalidRecipe(
                "version \(version) is not supported (this build reads version \(Recipe.currentVersion))")
        }
        for (name, value) in [("space", space), ("radius", radius), ("shadow", shadow)]
        where !(0...100).contains(value) {
            throw PremiumShotError.invalidRecipe("\(name) must be between 0 and 100, got \(value)")
        }
        for (name, value) in [("gradientFrom", gradientFrom), ("gradientTo", gradientTo)]
        where !(0...360).contains(value) {
            throw PremiumShotError.invalidRecipe("\(name) must be between 0 and 360, got \(value)")
        }
        guard redactions.isEmpty else {
            throw PremiumShotError.invalidRecipe("redactions are not supported yet")
        }
    }

    /// Strict decode: unknown look, shape or frame ids, wrong types, or out-of-range numbers all throw.
    public static func decodeStrict(_ data: Data) throws -> Recipe {
        let recipe: Recipe
        do { recipe = try JSONDecoder().decode(Recipe.self, from: data) } catch let error as PremiumShotError
        { throw error } catch { throw PremiumShotError.invalidRecipe(Recipe.describe(error)) }
        try recipe.validate()
        return recipe
    }

    /// Lenient decode used when the app loads its own saved state: clamp numbers, replace unknown ids with
    /// defaults, and fall back to the default recipe if the data is unusable or from a newer version.
    public static func decodeLenient(_ data: Data) -> Recipe {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .default
        }
        if let v = object["version"] as? Int, v != 1 && v != currentVersion { return .default }
        func number(_ key: String, _ fallback: Int, upper: Int = 100) -> Int {
            guard let n = object[key] as? NSNumber else { return fallback }
            return min(upper, max(0, n.intValue))
        }
        let look = (object["look"] as? String).flatMap(LookID.init(rawValue:)) ?? .dawn
        return Recipe(
            look: object["version"] as? Int == 1 && look == .custom ? .dawn : look,
            shape: (object["shape"] as? String).flatMap(Shape.init(rawValue:)) ?? .fit,
            space: number("space", 50), radius: number("radius", 50), shadow: number("shadow", 55),
            gradientFrom: object["version"] as? Int == 1 ? 155 : number("gradientFrom", 155, upper: 360),
            gradientTo: object["version"] as? Int == 1 ? 265 : number("gradientTo", 265, upper: 360))
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    private static func describe(_ error: Error) -> String {
        guard let e = error as? DecodingError else { return "\(error.localizedDescription)" }
        switch e {
        case .dataCorrupted(let c):
            let path = c.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? c.debugDescription : "unknown or invalid value for \"\(path)\""
        case .keyNotFound(let k, _): return "missing key \"\(k.stringValue)\""
        case .typeMismatch(_, let c), .valueNotFound(_, let c):
            return "wrong value for \"\(c.codingPath.map(\.stringValue).joined(separator: "."))\""
        @unknown default: return "unreadable recipe"
        }
    }
}
