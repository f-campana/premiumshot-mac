import AppKit
import PremiumShotCore
import XCTest

@testable import PremiumShotMac

@MainActor final class M11InteractionTests: XCTestCase {
    func testNativeControlsAreFocusableIndependentlyOfSystemKeyboardPreference() {
        let radio = RadioControl.Radio(
            labels: ["Fit", "16:9"], trackingMode: .selectOne, target: nil, action: nil)
        let slider = SliderControl.Control(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
        for control: NSControl in [radio, slider] {
            XCTAssertTrue(control.acceptsFirstResponder)
            XCTAssertTrue(control.canBecomeKeyView)
            control.isEnabled = false
            XCTAssertFalse(control.acceptsFirstResponder)
            XCTAssertFalse(control.canBecomeKeyView)
        }
    }
    func testOutsideClickDragEligibilityAndStationaryWatchdog() {
        var gesture = OutsideGesture()
        gesture.press(at: .zero, pasteboardCount: 42)
        XCTAssertEqual(gesture.pasteboardCount, 42)
        XCTAssertTrue(gesture.end())
        gesture.press(at: .zero, pasteboardCount: 43)
        gesture.move(to: CGPoint(x: 8, y: 0))
        XCTAssertEqual(gesture.phase, .unknown)
        XCTAssertFalse(gesture.end(buttonStillDown: true))
        XCTAssertEqual(gesture.phase, .unknown)
        gesture.classify(eligible: true)
        XCTAssertFalse(gesture.end())
        XCTAssertEqual(gesture.phase, .idle)
        gesture.press(at: .zero, pasteboardCount: 44)
        gesture.move(to: CGPoint(x: 5, y: 0))
        gesture.classify(eligible: false)
        XCTAssertTrue(gesture.end())
        gesture.press(at: .zero, pasteboardCount: 45)
        gesture.move(to: CGPoint(x: 5, y: 0))
        gesture.cancel()
        XCTAssertFalse(gesture.end())
    }
    func testExpansionClampKeepsTheCardInsideNegativeAndPositiveDisplays() {
        for area in [CGRect(x: -1440, y: 30, width: 1440, height: 870), CGRect(x: 0, y: -200, width: 1920, height: 1080)] {
            for size in [PanelMetrics.card, CGSize(width: 844, height: 412), CGSize(width: 960, height: 608)] {
                let proposed = CGRect(x: area.maxX-20, y: area.maxY-20, width: size.width, height: size.height)
                let placed = PanelPlacement.clamp(proposed, to: area)
                XCTAssertTrue(area.insetBy(dx: 12, dy: 12).contains(placed))
                XCTAssertEqual(placed.size, size)
            }
        }
    }
    func testPromisedImportsDiscardLateFilesAfterRemoveReplaceAndDismiss() async throws {
        for action in ["remove", "replace", "dismiss"] {
            let m = PanelModel(store: SessionStore())
            m.defaults = makeDefaults()
            putFixture("small-dialog.png", on: m)
            m.summon()
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
                "promise-test-\(UUID())")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("image.png")
            try FileManager.default.copyItem(at: Fixtures.url("wide-dashboard.png"), to: file)
            let receipt = PromisedImport(model: m, token: m.reserveImport(), folder: folder)
            receipt.expect(1)
            if action == "remove" {
                m.removeScreenshot()
            } else if action == "replace" {
                m.replace(with: try Fixtures.source("thin-strip.png"))
            } else {
                m.dismiss()
            }
            let token = m.state.token
            await receipt.receive(file)
            XCTAssertEqual(m.state.token, token, action)
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), action)
        }
    }
    func testPromisedBatchKeepsFolderUntilAllFilesAndFailureKeepsSource() async throws {
        let m = PanelModel(store: SessionStore())
        m.defaults = makeDefaults()
        putFixture("small-dialog.png", on: m)
        m.summon()
        let id = m.currentSession?.id
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("promise-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let first = folder.appendingPathComponent("invalid.png")
        let second = folder.appendingPathComponent("image.png")
        try Data("invalid image".utf8).write(to: first)
        try FileManager.default.copyItem(at: Fixtures.url("wide-dashboard.png"), to: second)
        let receipt = PromisedImport(model: m, token: m.reserveImport(), folder: folder)
        receipt.expect(2)
        await receipt.receive(first)
        XCTAssertEqual(m.currentSession?.id, id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        await receipt.receive(second)
        XCTAssertEqual(m.currentSession?.source.width, 2560)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        let failedFolder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "promise-test-\(UUID())")
        try FileManager.default.createDirectory(at: failedFolder, withIntermediateDirectories: true)
        let failed = PromisedImport(model: m, token: m.reserveImport(), folder: failedFolder)
        failed.expect(1)
        let current = m.currentSession?.id
        failed.expired()
        await failed.receive(failedFolder.appendingPathComponent("never-arrived.png"))
        XCTAssertEqual(m.currentSession?.id, current)
        XCTAssertFalse(m.isImporting)
        XCTAssertFalse(FileManager.default.fileExists(atPath: failedFolder.path))
    }
    func testFailedIncomingDecodeKeepsCommittedSourceAndRecipe() async throws {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let m = PanelModel(store: SessionStore())
        m.pasteboard = pb
        m.defaults = makeDefaults()
        putFixture("small-dialog.png", on: m)
        m.summon()
        for _ in 0..<100 where m.frame == nil { try? await Task.sleep(for: .milliseconds(10)) }
        let id = m.currentSession?.id
        let frame = m.frame
        let recipe = m.recipe
        let token = m.reserveImport()
        XCTAssertTrue(m.isReady)
        XCTAssertEqual(m.frame?.token, frame?.token)
        m.load(data: Data("invalid image".utf8), reservedToken: token)
        for _ in 0..<100 where m.isImporting { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(m.currentSession?.id, id)
        XCTAssertEqual(m.frame?.token, frame?.token)
        XCTAssertEqual(m.recipe, recipe)
        if case .error = m.status {} else { XCTFail("a failed drop should report its failure") }
    }
    func testFailedPromiseCallbackDoesNotDeleteItsUnspecifiedURL() async throws {
        let m = PanelModel(store: SessionStore())
        m.defaults = makeDefaults()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("promise-test-\(UUID())")
        let unrelated = FileManager.default.temporaryDirectory.appendingPathComponent(
            "promise-unrelated-\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: unrelated) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("preserve this file".utf8).write(to: unrelated)
        let receipt = PromisedImport(model: m, token: m.reserveImport(), folder: folder)
        receipt.expect(2)
        receipt.expired()
        await receipt.receive(unrelated, error: CocoaError(.fileReadUnknown))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        await receipt.receive(folder.appendingPathComponent("late.png"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
    func testAnimationInterruptionNeverCommitsAnOldTargetAndCopyFinishesIt() async throws {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let m = PanelModel(store: SessionStore())
        m.pasteboard = pb
        m.defaults = makeDefaults()
        putFixture("small-dialog.png", on: m)
        m.summon()
        for _ in 0..<100 where m.frame == nil { try? await Task.sleep(for: .milliseconds(10)) }
        m.edit { $0.shape = .wide }
        try? await Task.sleep(for: .milliseconds(40))
        m.edit {
            $0.shape = .square
        }
        await m.copy()
        XCTAssertEqual(m.frame?.recipe.shape, .square)
        XCTAssertNil(m.presentationImage)
        try? await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(m.frame?.recipe.shape, .square)
        let bytes = try XCTUnwrap(pb.data(forType: .png))
        let size = try XCTUnwrap(PNG.dimensions(bytes))
        XCTAssertEqual(size.width, 1080)
        XCTAssertEqual(size.height, 1080)
    }
    func testSpringStaysOnPathAndRetargetsWithoutReturningToOldGeometry() {
        let source = LayoutEngine.resolve(sourceWidth: 880, sourceHeight: 608, recipe: .default)
        var r = Recipe.default
        r.shape = .wide
        let target = LayoutEngine.resolve(sourceWidth: 880, sourceHeight: 608, recipe: r)
        let a = PresentationGeometry(source)
        let b = PresentationGeometry(target)
        var spring = CompositionMotion(from: a, to: b)
        for _ in 0..<8 { spring.advance(seconds: 0.016) }
        let middle = spring.geometry
        spring.retarget(a)
        XCTAssertEqual(spring.geometry, middle)
        for _ in 0..<60 { spring.advance(seconds: 0.016) }
        XCTAssertTrue(spring.finished)
        for (value, expected) in zip(spring.geometry.values, a.values) {
            XCTAssertEqual(value, expected, accuracy: 1e-8)
        }
    }
    func testThinToSquareAnimationKeepsTransientBitmapsInsideThePreviewBudget() async throws {
        let m = PanelModel(store: SessionStore())
        m.defaults = makeDefaults()
        putFixture("thin-strip.png", on: m)
        m.summon()
        for _ in 0..<200 where m.frame?.settled != true { try? await Task.sleep(for: .milliseconds(10)) }
        m.edit { $0.shape = .square }
        var observed = 0
        for _ in 0..<120 {
            if let image = m.presentationImage {
                observed += 1
                XCTAssertLessThanOrEqual(image.width, Int(PanelModel.canvasBox.width * m.backingScale) + 1)
                XCTAssertLessThanOrEqual(image.height, Int(PanelModel.canvasBox.height * m.backingScale) + 1)
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(observed, 0)
        XCTAssertEqual(m.frame?.recipe.shape, .square)
        XCTAssertNil(m.presentationImage)
    }
}
