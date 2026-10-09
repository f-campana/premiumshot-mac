import Foundation
import PremiumShotCore

/// A cache belongs to exactly one immutable source/recipe snapshot. Replacing it cannot return old work as new.
public actor RenderCache {
    public typealias Render = @Sendable (SourceImage, Recipe, ExportProfile) async throws -> RenderResult
    public typealias Encode = @Sendable (RenderResult) async throws -> Data
    private struct Key: Equatable {
        let source: ObjectIdentifier
        let recipe: Recipe
        let profile: ExportProfile
    }
    private var key: Key?
    private let encode: Encode
    public struct Output: Sendable {
        public let render: RenderResult
        public let png: Data
    }
    private let render: Render
    private var full: RenderResult?, png: Data?
    private var renderTask: Task<RenderResult, Error>?, encodeTask: Task<Data, Error>?
    private var invalidated = false
    public private(set) var renderCount = 0, encodeCount = 0
    public init(
        render: @escaping Render = { source, recipe, profile in
            try Renderer.render(source: source, recipe: recipe, profile: profile)
        }, encode: @escaping Encode = { try PNG.encode($0.image) }
    ) {
        self.render = render
        self.encode = encode
    }
    public func invalidate() {
        invalidated = true
        renderTask?.cancel()
        encodeTask?.cancel()
        full = nil
        png = nil
        renderTask = nil
        encodeTask = nil
    }
    public func resolved(source: SourceImage, recipe: Recipe, profile: ExportProfile) async throws
        -> RenderResult
    {
        guard !invalidated else { throw CancellationError() }
        let requested = Key(source: ObjectIdentifier(source), recipe: recipe, profile: profile)
        if key != requested {
            renderTask?.cancel()
            encodeTask?.cancel()
            full = nil
            png = nil
            renderTask = nil
            encodeTask = nil
            key = requested
        }
        if let full { return full }
        if renderTask == nil {
            renderCount += 1
            let render = self.render
            renderTask = Task.detached(priority: .userInitiated) { try await render(source, recipe, profile) }
        }
        let result = try await renderTask!.value
        guard !invalidated, key == requested else { throw CancellationError() }
        full = result
        renderTask = nil
        return result
    }
    public func preview(source: SourceImage, recipe: Recipe, profile: ExportProfile, height: Int) async throws
        -> RenderResult
    {
        let full = try await resolved(source: source, recipe: recipe, profile: profile)
        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return Renderer.preview(of: full, height: height)
        }.value
    }
    public func encoded(source: SourceImage, recipe: Recipe, profile: ExportProfile) async throws -> Output {
        let requested = Key(source: ObjectIdentifier(source), recipe: recipe, profile: profile)
        let result = try await resolved(source: source, recipe: recipe, profile: profile)
        guard key == requested, !invalidated else { throw CancellationError() }
        if let png { return Output(render: result, png: png) }
        if encodeTask == nil {
            encodeCount += 1
            let encode = self.encode
            encodeTask = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                return try await encode(result)
            }
        }
        let data = try await encodeTask!.value
        guard !invalidated, key == requested else { throw CancellationError() }
        png = data
        encodeTask = nil
        return Output(render: result, png: data)
    }
}
