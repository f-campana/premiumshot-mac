import AppKit
import PremiumShotCore
import XCTest

@testable import PremiumShotMac

private final class WeakSource {
    weak var value: SourceImage?
    init(_ value: SourceImage) { self.value = value }
}

private actor RenderGate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var opened = false
    func wait() async { if !opened { await withCheckedContinuation { waiting.append($0) } } }
    func open() {
        opened = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
    var started: Bool { !waiting.isEmpty }
}

@MainActor final class M1WorkflowTests: XCTestCase {
    func model(_ store: SessionStore = SessionStore(), pb: NSPasteboard) -> PanelModel {
        let model = PanelModel(store: store)
        model.pasteboard = pb
        model.defaults = makeDefaults()
        model.demoImageURL = Fixtures.url("small-dialog.png")
        return model
    }
    func wait(_ predicate: @escaping () -> Bool) async {
        for _ in 0..<200 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    func testReplacementClearsTheDisplayedPairAndCopyUsesNewSource() async throws {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let m = model(pb: pb)
        m.summon()
        await wait { m.preview != nil }
        let oldID = m.frame!.token.sessionID
        m.replace(with: try Fixtures.source("tall-article.png"))
        XCTAssertNil(m.frame)
        XCTAssertNil(m.layout)
        await m.copy()
        XCTAssertNotEqual(m.frame?.token.sessionID, oldID)
        let size = try XCTUnwrap(PNG.dimensions(try XCTUnwrap(pb.data(forType: .png))))
        XCTAssertEqual(size.width, m.layout?.width)
        XCTAssertEqual(size.height, m.layout?.height)
    }
    func testRemovePreservesStyleClipboardAndFileAndDropsSource() async throws {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let store = SessionStore()
        let m = model(store, pb: pb)
        let file = Fixtures.url("small-dialog.png")
        let before = try Data(contentsOf: file)
        pb.setString("keep me", forType: .string)
        let count = pb.changeCount
        m.summon()
        m.edit { $0.look = .tide }
        m.toggleDrawer()
        let source = WeakSource(m.currentSession!.source)
        m.removeScreenshot()
        XCTAssertEqual(m.phase, .empty(nil))
        XCTAssertEqual(m.recipe.look, .tide)
        XCTAssertFalse(m.isExpanded)
        XCTAssertNil(m.currentSession)
        XCTAssertNil(m.frame)
        XCTAssertEqual(store.count, 0)
        XCTAssertEqual(pb.changeCount, count)
        XCTAssertEqual(pb.string(forType: .string), "keep me")
        XCTAssertEqual(try Data(contentsOf: file), before)
        await wait { source.value == nil }
        XCTAssertNil(source.value)
    }
    func testSlowOutputCannotWriteOrResurrectAfterRemove() async throws {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let m = model(pb: pb)
        let gate = RenderGate()
        m.renderFull = { source, recipe, profile in
            await gate.wait()
            return try Renderer.render(source: source, recipe: recipe, profile: profile)
        }
        m.summon()
        let count = pb.changeCount
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = Task { await m.copy() }
        let save = Task { await m.save(to: folder) }
        let drag = Task { await m.prepareDrag() }
        for _ in 0..<100 {
            if await gate.started { break }
            await Task.yield()
        }
        m.removeScreenshot()
        await gate.open()
        await copy.value
        await save.value
        let dragResult = await drag.value
        XCTAssertNil(dragResult)
        XCTAssertEqual(pb.changeCount, count)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        XCTAssertNil(m.frame)
        XCTAssertNil(m.status)
        XCTAssertEqual(m.phase, .empty(nil))
    }
    func testSlowCopyIsAlsoDiscardedAfterStyleChangeOrDismiss() async throws {
        for dismiss in [false, true] {
            let pb = makePasteboard()
            defer { pb.releaseGlobally() }
            let gate = RenderGate()
            let m = model(pb: pb)
            m.renderFull = { source, recipe, profile in
                await gate.wait()
                return try Renderer.render(source: source, recipe: recipe, profile: profile)
            }
            m.summon()
            let count = pb.changeCount
            let task = Task { await m.copy() }
            for _ in 0..<100 {
                if await gate.started { break }
                await Task.yield()
            }
            if dismiss { m.dismiss() } else { m.edit { $0.look = .clear } }
            await gate.open()
            await task.value
            XCTAssertEqual(pb.changeCount, count)
            XCTAssertNil(m.status)
        }
    }
    func testSlowEncodingIsDiscardedAfterRemoveForEveryOutputAction() async throws {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let m = model(pb: pb)
        let gate = RenderGate()
        m.encodePNG = { result in
            await gate.wait()
            return try PNG.encode(result.image)
        }
        m.summon()
        let count = pb.changeCount
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = Task { await m.copy() }
        let save = Task { await m.save(to: folder) }
        let drag = Task { await m.prepareDrag() }
        for _ in 0..<200 {
            if await gate.started { break }
            try? await Task.sleep(for: .milliseconds(2))
        }
        let started = await gate.started
        XCTAssertTrue(started)
        m.removeScreenshot()
        await gate.open()
        await copy.value
        await save.value
        let dragURL = await drag.value
        XCTAssertNil(dragURL)
        XCTAssertEqual(pb.changeCount, count)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        XCTAssertNil(m.frame)
        XCTAssertNil(m.status)
    }
    func testReplacementKeepsDrawerAndStyleButClearsUndo() throws {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let m = model(pb: pb)
        m.summon()
        m.edit { $0.look = .tide }
        m.toggleDrawer()
        m.replace(with: try Fixtures.source("wide-dashboard.png"))
        XCTAssertTrue(m.isExpanded)
        XCTAssertEqual(m.recipe.look, .tide)
        m.undo()
        XCTAssertEqual(m.recipe.look, .tide)
    }
    func testPendingDropKeepsPreviewAndNewestReservationWins() async throws {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let m = model(pb: pb)
        m.summon()
        await wait { m.frame != nil }
        m.toggleDrawer()
        let old = m.currentSession!.id
        let priorFrame = m.frame
        let first = m.reserveImport()
        XCTAssertEqual(m.frame?.token, priorFrame?.token)
        XCTAssertTrue(m.isReady)
        let count = pb.changeCount
        await m.copy()
        XCTAssertGreaterThan(pb.changeCount, count)
        let second = m.reserveImport()
        m.load(data: try Fixtures.data("small-dialog.png"), reservedToken: first)
        XCTAssertTrue(m.isImporting)
        m.load(data: try Fixtures.data("tall-article.png"), reservedToken: second)
        await wait { !m.isImporting }
        XCTAssertNotEqual(m.currentSession?.id, old)
        XCTAssertEqual(m.currentSession?.source.height, 4262)
        XCTAssertTrue(m.isExpanded)
    }
    func testRemoveAlsoInvalidatesAnUnfulfilledDropProvider() async throws {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let m = model(pb: pb)
        m.summon()
        let pending = m.reserveImport()
        m.removeScreenshot()
        m.load(data: try Fixtures.data("small-dialog.png"), reservedToken: pending)
        await Task.yield()
        XCTAssertEqual(m.phase, .empty(nil))
        XCTAssertFalse(m.isImporting)
        XCTAssertNil(m.frame)
        XCTAssertNil(m.currentSession)
    }
    func testSummonAfterRemoveGuardsOurOutputButPlainImageImports() async throws {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let m = model(pb: pb)
        m.summon()
        await m.copy()
        m.removeScreenshot()
        m.demoImageURL = nil
        m.summon()
        XCTAssertEqual(m.phase, .alreadyPolished)
        pb.clearContents()
        pb.setData(try Fixtures.data("small-dialog.png"), forType: .png)
        m.summon()
        XCTAssertEqual(m.phase, .ready)
    }
    func testDeleteRoutingNeverConsumesOtherControlsOrInspect() {
        for key: UInt16 in [51, 117] {
            XCTAssertTrue(
                KeyRouting.shouldRemove(
                    keyCode: key, hasModifiers: false, previewFocused: true, inspecting: false))
            XCTAssertFalse(
                KeyRouting.shouldRemove(
                    keyCode: key, hasModifiers: true, previewFocused: true, inspecting: false))
            XCTAssertFalse(
                KeyRouting.shouldRemove(
                    keyCode: key, hasModifiers: false, previewFocused: false, inspecting: false))
            XCTAssertFalse(
                KeyRouting.shouldRemove(
                    keyCode: key, hasModifiers: false, previewFocused: true, inspecting: true))
        }
    }
    func testSliderHistoryCoalescesAndResetUndoRedoRestoresRecipe() {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let m = model(pb: pb)
        m.summon()
        m.beginSlider()
        for value in [30, 40, 80] { m.edit { $0.space = value } }
        m.endSlider()
        m.undo()
        XCTAssertEqual(m.recipe.space, 50)
        m.redo()
        XCTAssertEqual(m.recipe.space, 80)
        let prior = m.recipe
        m.resetLook()
        XCTAssertEqual(m.recipe, .default)
        m.undo()
        XCTAssertEqual(m.recipe, prior)
    }
    func testCachedRenderAndEncodingAreReusedAndExclusiveSaveDoesNotOverwrite() async throws {
        let source = try Fixtures.source("small-dialog.png")
        let cache = RenderCache()
        let first = try await cache.encoded(source: source, recipe: .default, profile: .srgb)
        let second = try await cache.encoded(source: source, recipe: .default, profile: .srgb)
        XCTAssertEqual(first.png, second.png)
        let renders = await cache.renderCount
        let encodes = await cache.encodeCount
        XCTAssertEqual(renders, 1)
        XCTAssertEqual(encodes, 1)
        let p3 = try await cache.encoded(source: source, recipe: .default, profile: .displayP3)
        XCTAssertEqual(p3.render.profile, .displayP3)
        let changedProfileRenders = await cache.renderCount
        XCTAssertEqual(changedProfileRenders, 2)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let date = Date(timeIntervalSince1970: 0)
        let a = try FileOutput.save(first.png, directory: dir, date: date)
        let b = try FileOutput.save(first.png, directory: dir, date: date)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(b.lastPathComponent.hasSuffix(" 2.png"))
        XCTAssertEqual(try Data(contentsOf: a), first.png)
        XCTAssertThrowsError(try FileOutput.save(first.png, directory: dir.appendingPathComponent("missing")))
    }
    func testPureStateTokensCoverEveryInvalidatingTransition() {
        var state = PanelState()
        state.transition(to: .ready(UUID()))
        let initial = state.token
        var next = state.recipe
        next.look = .clear
        state.changeRecipe(next)
        XCTAssertNotEqual(initial, state.token)
        let styled = state.token
        state.transition(to: .empty(nil))
        XCTAssertNotEqual(styled, state.token)
        XCTAssertEqual(state.recipe, next)
        let empty = state.token
        state.transition(to: .hidden)
        XCTAssertNotEqual(empty, state.token)
    }
    func testCopySaveAndDragShareTheResolvedSizeAndOneEncoding() async throws {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let m = model(pb: pb)
        m.summon()
        m.edit {
            $0.look = .clear
            $0.shape = .square
        }
        await m.copy()
        let size = try XCTUnwrap(m.layout)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        await m.save(to: folder)
        let file = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        let preparedDrag = await m.prepareDrag()
        let drag = try XCTUnwrap(preparedDrag)
        defer { try? FileManager.default.removeItem(at: drag) }
        for bytes in [
            try XCTUnwrap(pb.data(forType: .png)), try Data(contentsOf: file), try Data(contentsOf: drag),
        ] {
            let dimensions = try XCTUnwrap(PNG.dimensions(bytes))
            XCTAssertEqual(dimensions.width, size.width)
            XCTAssertEqual(dimensions.height, size.height)
            let decoded = try XCTUnwrap(PNG.inspect(bytes))
            XCTAssertTrue(
                [.first, .last, .premultipliedFirst, .premultipliedLast].contains(decoded.image.alphaInfo))
        }
        let metrics = await m.renderMetrics()
        XCTAssertEqual(metrics.renderCount, 1)
        XCTAssertEqual(metrics.encodeCount, 1)
    }
}
