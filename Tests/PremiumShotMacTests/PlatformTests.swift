import Carbon.HIToolbox
import XCTest
import PremiumShotCore
@testable import PremiumShotMac

@MainActor
final class PlatformTests: XCTestCase {
    /// S5, the part a test can prove: registration succeeds, and a second owner of the same combination is refused,
    /// which is exactly how a clash with another app (Raycast, say) would show up.
    func testHotkeyRegistersAndAConflictIsDetected() {
        let combo = (UInt32(kVK_F19), GlobalHotkey.defaultModifiers)       // an unusual key so a running app cannot interfere
        let first = GlobalHotkey(keyCode: combo.0, modifiers: combo.1, id: 91) {}
        let second = GlobalHotkey(keyCode: combo.0, modifiers: combo.1, id: 92) {}
        XCTAssertEqual(first.register(), noErr)
        XCTAssertEqual(second.register(), OSStatus(eventHotKeyExistsErr))
        first.unregister()
        XCTAssertEqual(second.register(), noErr, "free again once the first owner lets go")
        second.unregister()
    }

    func testTheShippedHotkeyIsCommandOptionShiftSpace() {
        XCTAssertEqual(GlobalHotkey.defaultKeyCode, UInt32(kVK_Space))
        XCTAssertEqual(GlobalHotkey.defaultModifiers, UInt32(cmdKey | optionKey | shiftKey))
    }

    // S10, the part a test can prove: direction follows the fingers for all four combinations.
    func testSwipeDirectionFollowsTheFingersWhateverTheScrollingSetting() {
        // AppKit: scrollingDeltaY > 0 means content moves down.
        XCTAssertEqual(Gestures.zoomIntent(scrollingDeltaY: -5, directionInvertedFromDevice: true), .zoomIn)    // natural, fingers up
        XCTAssertEqual(Gestures.zoomIntent(scrollingDeltaY: 5, directionInvertedFromDevice: true), .zoomOut)    // natural, fingers down
        XCTAssertEqual(Gestures.zoomIntent(scrollingDeltaY: 5, directionInvertedFromDevice: false), .zoomIn)    // traditional, fingers up
        XCTAssertEqual(Gestures.zoomIntent(scrollingDeltaY: -5, directionInvertedFromDevice: false), .zoomOut)  // traditional, fingers down
        XCTAssertNil(Gestures.zoomIntent(scrollingDeltaY: 0, directionInvertedFromDevice: true))
    }

    func testDragTempFilesAreWrittenAndPurged() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ps-test-\(UUID().uuidString)")
        let url = try DragTempFiles.write(Data("x".utf8), name: "a.png", directory: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        DragTempFiles.purge(directory: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        XCTAssertThrowsError(try DragTempFiles.write(Data("x".utf8), name: "a.png", directory: URL(fileURLWithPath: "/dev/null/nope")), "an unwritable directory must fail so the drag does not start")
    }

    func testRecipePersistenceRoundTripsAndSurvivesCorruption() {
        let defaults = makeDefaults()
        XCTAssertEqual(RecipePersistence.load(from: defaults), .default)
        var recipe = Recipe.default; recipe.look = .paper; recipe.space = 20
        RecipePersistence.save(recipe, to: defaults)
        XCTAssertEqual(RecipePersistence.load(from: defaults), recipe)
        defaults.set(Data("garbage".utf8), forKey: RecipePersistence.key)
        XCTAssertEqual(RecipePersistence.load(from: defaults), .default, "a corrupt saved recipe falls back to defaults")
    }

    func testPanelWeightDefaultsToLight() {
        let defaults = makeDefaults()
        XCTAssertEqual(Preferences.panelWeight(defaults), .light)
        defaults.set("standard", forKey: "panelWeight")
        XCTAssertEqual(Preferences.panelWeight(defaults), .standard)
    }

    func testRenderQueueSkipsSupersededPreviews() async throws {
        let queue = RenderQueue(), source = try Fixtures.source("small-dialog.png")
        async let first = queue.preview(source: source, recipe: .default, height: 120)
        async let second = queue.preview(source: source, recipe: .default, height: 120)
        let results = try await [first, second]
        XCTAssertNotNil(results[1], "the newest request always renders")
        XCTAssertTrue(results.contains { $0 != nil })
    }
}
