import Foundation
import PremiumShotCore

/// pshot: renders and inspects the same output the app produces, without opening the app.
/// Exit codes: 0 ok, 2 usage or validation error, 3 input unreadable or unsupported, 4 input too large, 5 write failed.

struct UsageError: Error { let message: String }

let usageText = """
usage:
  pshot render --in <image> --out <file.png> [recipe options] [--export-profile srgb|p3] [--json]
  pshot layout --in <image> [recipe options] [--export-profile srgb|p3] [--json]
  pshot validate <recipe.json>
  pshot bench --in <image> [recipe options] [--export-profile srgb|p3] [--runs N]    # per-stage timings in ms, as JSON

recipe options (either a file, or individual values over the defaults, not both):
  --recipe <recipe.json>
  --look dawn|tide|paper|graphite|clear   --shape fit|16:9|4:5|1:1|1.91:1
  --space 0-100  --radius 0-100  --shadow 0-100  --frame none|window|browser
"""

struct Options {
    var values: [String: String] = [:]
    var json = false
    var positional: [String] = []

    init(_ args: [String]) throws {
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--json" { json = true }
            else if a.hasPrefix("--") {
                guard i + 1 < args.count else { throw UsageError(message: "\(a) needs a value") }
                values[String(a.dropFirst(2))] = args[i + 1]; i += 1
            } else { positional.append(a) }
            i += 1
        }
    }

    func require(_ key: String) throws -> String {
        guard let v = values[key] else { throw UsageError(message: "--\(key) is required") }
        return v
    }

    static let recipeKeys = ["look", "shape", "space", "radius", "shadow", "frame"]
    static let knownKeys = Set(recipeKeys + ["in", "out", "recipe", "export-profile", "runs"])

    func profile() throws -> ExportProfile {
        guard let v = values["export-profile"] else { return .srgb }
        guard let p = ExportProfile(rawValue: v) else { throw UsageError(message: "--export-profile must be srgb or p3") }
        return p
    }

    func recipe() throws -> Recipe {
        for key in values.keys where !Options.knownKeys.contains(key) { throw UsageError(message: "unknown option --\(key)") }
        if let path = values["recipe"] {
            guard Options.recipeKeys.allSatisfy({ values[$0] == nil }) else {
                throw UsageError(message: "use --recipe or individual recipe options, not both")
            }
            guard let data = FileManager.default.contents(atPath: path) else {
                throw UsageError(message: "cannot read recipe file \(path)")
            }
            return try Recipe.decodeStrict(data)
        }
        var r = Recipe.default
        if let v = values["look"] { guard let x = LookID(rawValue: v) else { throw PremiumShotError.invalidRecipe("unknown look \"\(v)\"") }; r.look = x }
        if let v = values["shape"] { guard let x = Shape(rawValue: v) else { throw PremiumShotError.invalidRecipe("unknown shape \"\(v)\"") }; r.shape = x }
        if let v = values["frame"] { guard let x = Frame(rawValue: v) else { throw PremiumShotError.invalidRecipe("unknown frame \"\(v)\"") }; r.frame = x }
        for (key, keyPath) in [("space", \Recipe.space), ("radius", \Recipe.radius), ("shadow", \Recipe.shadow)] {
            if let v = values[key] {
                guard let n = Int(v) else { throw PremiumShotError.invalidRecipe("--\(key) must be an integer, got \"\(v)\"") }
                r[keyPath: keyPath] = n
            }
        }
        try r.validate()
        return r
    }
}

struct ResolvedSpec: Codable {
    let width: Int, height: Int, capped: Bool, screenshotScale: Double, profile: String
    init(_ layout: Layout, _ profile: ExportProfile) {
        width = layout.width; height = layout.height; capped = layout.capped
        screenshotScale = (layout.screenshotScale * 10_000).rounded() / 10_000
        self.profile = profile.rawValue == "p3" ? "p3" : "srgb"
    }
    var line: String { "\(width) × \(height) px, screenshot at \(Int((screenshotScale * 100).rounded()))%\(capped ? ", capped" : ""), \(profile)" }
    func json() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

func run() throws {
    var args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else { throw UsageError(message: "no command given") }
    args.removeFirst()
    let options = try Options(args)

    switch command {
    case "validate":
        guard let path = options.positional.first else { throw UsageError(message: "validate needs a recipe file") }
        guard let data = FileManager.default.contents(atPath: path) else { throw UsageError(message: "cannot read recipe file \(path)") }
        _ = try Recipe.decodeStrict(data)
        print("ok")
    case "layout":
        let recipe = try options.recipe(), profile = try options.profile()
        let source = try ImageLoader.load(url: URL(fileURLWithPath: try options.require("in")))
        let spec = ResolvedSpec(LayoutEngine.resolve(sourceWidth: source.width, sourceHeight: source.height, recipe: recipe), profile)
        print(options.json ? try spec.json() : spec.line)
    case "render":
        let recipe = try options.recipe(), profile = try options.profile()
        let outURL = URL(fileURLWithPath: try options.require("out"))
        let source = try ImageLoader.load(url: URL(fileURLWithPath: try options.require("in")))
        let result = try Renderer.render(source: source, recipe: recipe, profile: profile)
        try PNG.write(try PNG.encode(result.image), to: outURL)
        let spec = ResolvedSpec(result.layout, profile)
        print(options.json ? try spec.json() : "wrote \(outURL.path): \(spec.line)")
    case "bench":
        // Evidence for the performance budgets: decode, layout, render and PNG encode timed separately.
        let recipe = try options.recipe(), profile = try options.profile()
        let runs = max(1, Int(options.values["runs"] ?? "") ?? 5)
        let path = try options.require("in")
        let clock = ContinuousClock()
        func ms(_ d: Duration) -> Double { (Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 * 10).rounded() / 10 }
        var decode = [Double](), render = [Double](), encode = [Double](), size = ""
        for _ in 0..<runs {
            var source: SourceImage?
            decode.append(ms(try clock.measure { source = try ImageLoader.load(url: URL(fileURLWithPath: path)) }))
            var result: RenderResult?
            render.append(ms(try clock.measure { result = try Renderer.render(source: source!, recipe: recipe, profile: profile) }))
            encode.append(ms(try clock.measure { _ = try PNG.encode(result!.image) }))
            size = "\(result!.layout.width)x\(result!.layout.height)"
        }
        func median(_ a: [Double]) -> Double { a.sorted()[a.count / 2] }
        print("{\"decodeMs\":\(median(decode)),\"encodeMs\":\(median(encode)),\"output\":\"\(size)\",\"renderMs\":\(median(render)),\"runs\":\(runs)}")
    case "help", "--help", "-h":
        print(usageText)
    default:
        throw UsageError(message: "unknown command \"\(command)\"")
    }
}

do { try run() }
catch let e as UsageError {
    FileHandle.standardError.write(Data("pshot: \(e.message)\n\(usageText)\n".utf8)); exit(2)
}
catch let e as PremiumShotError {
    FileHandle.standardError.write(Data("pshot: \(e.localizedDescription)\n".utf8)); exit(e.exitCode)
}
catch {
    FileHandle.standardError.write(Data("pshot: \(error.localizedDescription)\n".utf8)); exit(1)
}
