import AppKit
import XCTest
import PremiumShotCore
@testable import PremiumShotMac

/// I2: Copy reports success only after the pasteboard write succeeded. Also R2 on the real Copy path.
@MainActor
final class ModelTests: XCTestCase {
    func makeModel(image: String = "small-dialog.png", pasteboard: NSPasteboard) -> PanelModel {
        let model = PanelModel(store: SessionStore())
        model.pasteboard = pasteboard; model.defaults = makeDefaults()
        model.demoImageURL = Fixtures.url(image)
        return model
    }

    func waitForPreview(_ model: PanelModel) async {
        for _ in 0..<200 where model.preview == nil { try? await Task.sleep(for: .milliseconds(25)) }
    }

    func testSummonShowsAPreviewAtTheResolvedAspect() async throws {
        let pb = makePasteboard(); defer { pb.releaseGlobally() }
        let model = makeModel(pasteboard: pb)
        model.summon()
        XCTAssertEqual(model.phase, .ready)
        await waitForPreview(model)
        let preview = try XCTUnwrap(model.preview), layout = try XCTUnwrap(model.layout)
        XCTAssertEqual(Double(preview.width) / Double(preview.height), Double(layout.width) / Double(layout.height), accuracy: 0.01)
    }

    func testCopyConfirmsOnlyAfterTheWriteAndTheClipboardMatchesTheCaption() async throws {
        let pb = makePasteboard(); defer { pb.releaseGlobally() }
        let model = makeModel(pasteboard: pb)
        model.summon()
        XCTAssertNil(model.status)
        await model.copy()
        let layout = try XCTUnwrap(model.layout)
        XCTAssertEqual(model.status, .copied("Copied \(layout.width) × \(layout.height) px"))
        let decoded = try XCTUnwrap(PNG.inspect(try XCTUnwrap(pb.data(forType: .png))))
        XCTAssertEqual(decoded.image.width, layout.width); XCTAssertEqual(decoded.image.height, layout.height)   // R2
        XCTAssertEqual(PasteboardIO.marker(on: pb), model.currentSession?.id)
    }

    func testAForcedPasteboardFailureShowsAnErrorNotSuccess() async throws {
        let pb = makePasteboard(); defer { pb.releaseGlobally() }
        let model = makeModel(pasteboard: pb)
        model.pasteboardWriter = { _, _, _, _ in false }
        model.summon()
        await model.copy()
        XCTAssertEqual(model.status, .error("Couldn't copy to the clipboard."))
        if case .copied? = model.status { XCTFail("must not claim success") }
    }

    func testTheLastRecipeIsRestoredOnTheNextSummon() async throws {
        let pb = makePasteboard(); defer { pb.releaseGlobally() }
        let model = makeModel(pasteboard: pb)
        var chosen = Recipe.default; chosen.look = .graphite; chosen.shape = .wide
        RecipePersistence.save(chosen, to: model.defaults)
        model.summon()
        await waitForPreview(model)
        XCTAssertEqual(model.recipe.look, .graphite); XCTAssertEqual(model.recipe.shape, .wide)
        XCTAssertEqual(model.layout?.width, 1920)
    }

    func testAlreadyPolishedClipboardOffersUseItAnyway() async throws {
        let pb = makePasteboard(); defer { pb.releaseGlobally() }
        let model = PanelModel(store: SessionStore()); model.pasteboard = pb; model.defaults = makeDefaults()
        let result = try Renderer.render(source: try Fixtures.source("thin-strip.png"), recipe: .default)
        PasteboardIO.writePNG(try PNG.encode(result.image), marker: UUID(), expectedSize: (result.layout.width, result.layout.height), to: pb)
        model.summon()
        XCTAssertEqual(model.phase, .alreadyPolished)
        model.useAlreadyPolishedAnyway()
        XCTAssertEqual(model.phase, .ready)
    }

    func testEmptyClipboardShowsTheEmptyState() {
        let pb = makePasteboard(); defer { pb.releaseGlobally() }
        let model = PanelModel(store: SessionStore()); model.pasteboard = pb; model.defaults = makeDefaults()
        model.summon()
        XCTAssertEqual(model.phase, .empty(nil))
    }
}
