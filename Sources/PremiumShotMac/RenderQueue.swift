import CoreGraphics
import Foundation
import PremiumShotCore

/// Bounded background rendering. Previews run one at a time and **latest wins**: a request that has been
/// superseded by the time its turn comes is skipped. Exports run outside the queue so they never wait behind
/// (or block) previews.
public actor RenderQueue {
    private var generation = 0
    public init() {}

    /// Returns nil when a newer preview request arrived first.
    public func preview(source: SourceImage, recipe: Recipe, profile: ExportProfile = .srgb, height: Int) async throws -> RenderResult? {
        generation += 1
        let mine = generation
        await Task.yield()                      // let any newer request register before we start
        guard mine == generation else { return nil }
        return try Renderer.renderPreview(source: source, recipe: recipe, profile: profile, height: height)
    }

    /// Full-size render for Copy, Save and drag-out.
    public nonisolated func export(source: SourceImage, recipe: Recipe, profile: ExportProfile = .srgb) async throws -> RenderResult {
        try await Task.detached(priority: .userInitiated) {
            try Renderer.render(source: source, recipe: recipe, profile: profile)
        }.value
    }
}
