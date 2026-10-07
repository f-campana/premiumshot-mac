import AppKit
import XCTest
import PremiumShotCore
@testable import PremiumShotMac

/// I6: re-summon after Copy reopens the matching source session; without one it says "already polished".
@MainActor
final class SessionTests: XCTestCase {
    func testPlainImageEmptyAndAlreadyPolishedAndSessionCases() throws {
        let store = SessionStore()
        let source = try Fixtures.source("small-dialog.png")

        let plain = makePasteboard(); defer { plain.releaseGlobally() }
        plain.setData(try Fixtures.data("small-dialog.png"), forType: .png)
        guard case .image = SummonSource.resolve(pasteboard: plain, store: store) else { return XCTFail("plain image") }

        guard case .empty = SummonSource.resolve(pasteboard: makePasteboard(), store: store) else { return XCTFail("empty") }

        // Our own output whose session is retained: reopen it, with its recipe.
        var recipe = Recipe.default; recipe.look = .tide
        let session = store.add(source: source, recipe: recipe)
        let ours = makePasteboard(); defer { ours.releaseGlobally() }
        let polished = try Renderer.render(source: source, recipe: recipe)
        PasteboardIO.writePNG(try PNG.encode(polished.image), marker: session.id, expectedSize: (polished.layout.width, polished.layout.height), to: ours)
        guard case .session(let reopened) = SummonSource.resolve(pasteboard: ours, store: store) else { return XCTFail("session") }
        XCTAssertEqual(reopened.id, session.id); XCTAssertEqual(reopened.recipe.look, .tide)
        XCTAssertEqual(reopened.source.width, source.width, "the original is reopened, not the polished image")

        // Our own output but no session (after a restart): offer "use it anyway".
        guard case .alreadyPolished = SummonSource.resolve(pasteboard: ours, store: SessionStore()) else { return XCTFail("already polished") }
    }

    func testStoreKeepsOnlyTheLastThreeSessions() throws {
        let store = SessionStore(), source = try Fixtures.source("thin-strip.png")
        let ids = (0..<5).map { _ in store.add(source: source, recipe: .default).id }
        XCTAssertEqual(store.count, 3)
        XCTAssertNil(store.session(id: ids[0])); XCTAssertNil(store.session(id: ids[1]))
        XCTAssertNotNil(store.session(id: ids[4]))
    }
}
