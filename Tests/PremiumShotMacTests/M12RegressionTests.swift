import AppKit
import PremiumShotCore
import SwiftUI
import UniformTypeIdentifiers
import XCTest

@testable import PremiumShotMac

@MainActor final class M12RegressionTests: XCTestCase {
    func event(_ keyCode: UInt16, text: String, flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
                isARepeat: false, keyCode: keyCode))
    }
    func makeModel() throws -> PanelModel {
        let model = PanelModel(store: SessionStore())
        model.defaults = makeDefaults()
        model.replace(with: try Fixtures.source("small-dialog.png"))
        return model
    }
    func testUndoRedoFollowsLettersOnAzertyAndOtherKeyboardLayouts() throws {
        let model = try makeModel()
        let controller = PanelController(model: model)
        let original = model.recipe
        model.edit { $0.look = .tide }
        let edited = model.recipe
        // French AZERTY's Z is physical key 13 (W on QWERTY).
        XCTAssertTrue(controller.handle(try event(13, text: "z", flags: .command)))
        XCTAssertEqual(model.recipe, original)
        XCTAssertTrue(controller.handle(try event(13, text: "Z", flags: [.command, .shift])))
        XCTAssertEqual(model.recipe, edited)
        XCTAssertFalse(controller.handle(try event(6, text: "w", flags: .command)))
        XCTAssertEqual(model.recipe, edited, "A physical QWERTY Z must not undo a typed W")
        model.dismiss()
    }
    func testCustomButtonsObeyRealHostingViewFramesInEveryPanelState() async throws {
        let model = try makeModel()
        for _ in 0..<200 where model.frame == nil { try await Task.sleep(for: .milliseconds(10)) }
        model.focus = .preview
        let panel = FloatingPanel(size: PanelMetrics.card)
        let host = NSHostingView(rootView: PanelView(model: model))
        host.sizingOptions = []
        let background = NSView(frame: NSRect(origin: .zero, size: PanelMetrics.card))
        background.wantsLayer = true
        host.autoresizingMask = [.width, .height]
        background.addSubview(host)
        panel.contentView = background
        defer {
            panel.contentView = nil
            model.dismiss()
        }
        @MainActor func buttons(in view: NSView) -> [ActionButton] {
            (view as? ActionButton).map { [$0] } ?? view.subviews.flatMap(buttons)
        }
        for dark in [false, true] {
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            background.layer?.backgroundColor =
                NSColor(
                    srgbRed: dark ? 0.16 : 0.94, green: dark ? 0.16 : 0.94,
                    blue: dark ? 0.17 : 0.95, alpha: 1
                ).cgColor
            if !model.isReady {
                model.replace(with: try Fixtures.source("small-dialog.png"))
                for _ in 0..<200 where model.frame == nil { try await Task.sleep(for: .milliseconds(10)) }
                model.focus = .preview
            }
            for state in ["compact", "expanded", "empty"] {
                let expanded = state == "expanded"
                if state == "empty" { model.removeScreenshot() }
                if model.isExpanded != expanded { model.toggleDrawer() }
                let size = NSSize(width: expanded ? 844 : 600, height: 412)
                panel.setContentSize(size)
                host.frame = NSRect(origin: .zero, size: size)
                for _ in 0..<20 {
                    host.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(10))
                }
                let controls = buttons(in: host)
                let looks = controls.filter { $0.identifier?.rawValue.hasPrefix("ps.look-") == true }
                XCTAssertEqual(looks.count, 6)
                for swatch in looks {
                    XCTAssertEqual(swatch.frame.size, NSSize(width: 38, height: 32), swatch.title)
                    XCTAssertEqual(swatch.intrinsicContentSize.width, NSView.noIntrinsicMetric)
                }
                let swatchRects = looks.map { host.convert($0.bounds, from: $0) }.sorted { $0.minX < $1.minX }
                for i in 1..<swatchRects.count {
                    XCTAssertEqual(swatchRects[i].minX - swatchRects[i - 1].maxX, 2, accuracy: 0.01)
                }
                for (id, size) in [
                    ("remove", NSSize(width: 28, height: 28)),
                    ("inspect", NSSize(width: 28, height: 28)),
                    ("adjust", NSSize(width: 64, height: 38)),
                    ("save", NSSize(width: 54, height: 38)),
                    ("copy", NSSize(width: 106, height: 38)),
                ] {
                    if state == "empty" && ["remove", "inspect"].contains(id) { continue }
                    let control = try XCTUnwrap(controls.first { $0.identifier?.rawValue == "ps.\(id)" })
                    XCTAssertEqual(control.frame.size, size, id)
                    XCTAssertEqual(control.isEnabled, state != "empty")
                }
                if expanded {
                    let randomize = try XCTUnwrap(
                        controls.first { $0.identifier?.rawValue == "ps.randomize" })
                    XCTAssertEqual(randomize.frame.size, NSSize(width: 32, height: 32))
                }
                if let path = ProcessInfo.processInfo.environment["M12_REGRESSION_DIR"],
                    let bitmap = background.bitmapImageRepForCachingDisplay(in: background.bounds)
                {
                    background.cacheDisplay(in: background.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                        to: URL(fileURLWithPath: path).appendingPathComponent(
                            "hosted-\(dark ? "dark" : "light")-\(state).png"))
                }
            }
        }
    }
    func testImagePromiseWinsOverUnfinishedURLAndNonImageBytes() async throws {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        let delegate = TestPromiseDelegate()
        let provider = NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: delegate)
        let unfinished = NSPasteboardItem()
        unfinished.setString("file:///not-ready/screenshot.png", forType: .fileURL)
        unfinished.setData(Data("unfinished image representation".utf8), forType: .tiff)
        XCTAssertTrue(board.writeObjects([provider, unfinished]))
        let receivers = try XCTUnwrap(
            board.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver])
        XCTAssertEqual(receivers.count, 1)
        XCTAssertEqual(receivers.first?.fileTypes, [UTType.png.identifier])
        XCTAssertTrue(
            PanelMaterialView.eligible(board), "A valid promise takes precedence over its unfinished URL")
        let model = try makeModel()
        // AppKit's writing service requires a real interactive dragging session.
        // Use its actual promise metadata with a deterministic delivery transport here.
        var requested = 0
        let destination = PanelMaterialView(model: model) { _, folder, reader in
            requested += 1
            let file = folder.appendingPathComponent("screenshot.png")
            do {
                try FileManager.default.copyItem(at: Fixtures.url("wide-dashboard.png"), to: file)
                reader(file, nil)
            } catch { reader(file, error) }
        }
        let drag = TestDragInfo(board: board)
        XCTAssertEqual(destination.draggingEntered(drag), .copy)
        XCTAssertTrue(destination.prepareForDragOperation(drag))
        XCTAssertTrue(destination.performDragOperation(drag))
        for _ in 0..<300 where model.isImporting { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.currentSession?.source.width, 2560)
        XCTAssertEqual(requested, 1)
        XCTAssertFalse(model.status.map { if case .error = $0 { true } else { false } } ?? false)
        model.dismiss()
    }
    func testUnsupportedPromiseDoesNotHighlightItsAccompanyingIcon() throws {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        let delegate = TestPromiseDelegate()
        let provider = NSFilePromiseProvider(fileType: UTType.plainText.identifier, delegate: delegate)
        let icon = NSPasteboardItem()
        icon.setData(try Fixtures.tiffData("thin-strip.png"), forType: .tiff)
        XCTAssertTrue(board.writeObjects([provider, icon]))
        XCTAssertFalse(PanelMaterialView.eligible(board))
        let model = try makeModel()
        let destination = PanelMaterialView(model: model)
        let drag = TestDragInfo(board: board)
        XCTAssertEqual(destination.draggingEntered(drag), [])
        XCTAssertFalse(destination.prepareForDragOperation(drag))
        XCTAssertFalse(destination.performDragOperation(drag))
        XCTAssertFalse(model.dropTarget)
        XCTAssertEqual(model.currentSession?.source.width, 880)
        model.dismiss()
    }
}

private final class TestPromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    @MainActor func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String
    ) -> String {
        "screenshot.png"
    }
    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            try FileManager.default.copyItem(at: Fixtures.url("wide-dashboard.png"), to: url)
            completionHandler(nil)
        } catch { completionHandler(error) }
    }
}

@MainActor private final class TestDragInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    init(board: NSPasteboard) { draggingPasteboard = board }
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    nonisolated var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? {
        nil
    }
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func resetSpringLoading() {}
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?,
        classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
}
