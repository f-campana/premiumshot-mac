import AppKit
import PremiumShotCore
import SwiftUI
import XCTest

@testable import PremiumShotMac

@MainActor final class M12InteractionTests: XCTestCase {
    func model() throws -> PanelModel {
        let model = PanelModel(store: SessionStore())
        model.defaults = makeDefaults()
        model.replace(with: try Fixtures.source("small-dialog.png"))
        return model
    }
    func window() -> NSPanel {
        NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 412),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    }
    func key(_ code: UInt16, characters: String = "", flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }
    func testApprovedNativeKeyLoopAndDisabledSemantics() throws {
        let model = try model()
        let window = window()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 412))
        window.contentView = root
        var buttons: [String: ActionButton] = [:]
        for id in PanelKeyLoop.order.reversed() {
            let button = ActionButton(model: model)
            button.identifier = .init("ps.\(id)")
            root.addSubview(button)
            buttons[id] = button
        }
        XCTAssertEqual(PanelKeyLoop.configure(root: root, window: window), PanelKeyLoop.order)
        for (i, id) in PanelKeyLoop.order.enumerated() {
            XCTAssertTrue(
                buttons[id]?.nextKeyView === buttons[PanelKeyLoop.order[(i + 1) % PanelKeyLoop.order.count]])
        }
        for button in buttons.values { button.isEnabled = false }
        XCTAssertTrue(PanelKeyLoop.configure(root: root, window: window).isEmpty)
        XCTAssertTrue(
            buttons.values.allSatisfy {
                !$0.acceptsFirstResponder && !$0.canBecomeKeyView && !$0.isAccessibilityEnabled()
            })
    }
    func testOverlappingHandlesRemainSeparateAndKeyboardBurstHasOneUndo() throws {
        let model = try model()
        let window = window()
        model.edit {
            $0.look = .custom
            $0.gradientFrom = 155
            $0.gradientTo = 155
        }
        let before = model.recipe
        let strip = HueStripView(model: model)
        window.contentView?.addSubview(strip)
        strip.update(enabled: true)
        XCTAssertEqual(strip.start.frame, strip.end.frame)
        XCTAssertEqual(strip.start.accessibilityLabel(), "Gradient start")
        XCTAssertEqual(strip.end.accessibilityLabel(), "Gradient end")
        XCTAssertTrue(window.makeFirstResponder(strip.start))
        XCTAssertTrue(strip.start.accessibilityPerformIncrement())
        XCTAssertTrue(strip.start.accessibilityPerformIncrement())
        strip.start.keyDown(with: try key(124, flags: .shift))
        XCTAssertEqual(model.recipe.gradientFrom, 167)
        XCTAssertEqual(model.recipe.gradientTo, 155)
        strip.start.keyDown(with: try key(51))
        XCTAssertTrue(model.isReady, "Delete on a hue slider never removes the source")
        strip.endKeyboardBurst()
        model.undo()
        XCTAssertEqual(model.recipe, before)
        model.redo()
        XCTAssertEqual(model.recipe.gradientFrom, 167)
        XCTAssertTrue(window.makeFirstResponder(strip.end))
        XCTAssertTrue(strip.end.accessibilityPerformDecrement())
        XCTAssertEqual(model.recipe.gradientTo, 154)
        strip.endKeyboardBurst()
        strip.update(enabled: false)
        let disabled = model.recipe
        XCTAssertFalse(strip.end.accessibilityPerformIncrement())
        XCTAssertEqual(model.recipe, disabled)
        XCTAssertFalse(strip.end.canBecomeKeyView)
        strip.set(300, on: strip.start)
        strip.set(30, on: strip.end)
        XCTAssertEqual(model.recipe.gradientFrom, 300)
        XCTAssertEqual(model.recipe.gradientTo, 30, "Crossing never swaps endpoint identities")
    }
    func testRandomizeCommitsOneUndoAndCopyInspectSnapToCurrentRecipe() async throws {
        let model = try model()
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        model.pasteboard = pb
        for _ in 0..<200 where model.frame == nil { try await Task.sleep(for: .milliseconds(10)) }
        let before = model.recipe
        let strip = HueStripView(model: model)
        strip.update(enabled: true)
        var rng = Seeded(state: 17)
        model.randomizeGradient(using: &rng)
        strip.update(enabled: true)
        let first = model.recipe
        XCTAssertEqual(first.look, .custom)
        await model.copy()
        strip.update(enabled: true)
        XCTAssertFalse(model.gradientPresentationActive)
        XCTAssertEqual(strip.start.positionHue, Double(first.gradientFrom))
        XCTAssertEqual(strip.end.positionHue, Double(first.gradientTo))
        XCTAssertNil(model.presentationImage)
        XCTAssertEqual(model.frame?.recipe, first)
        let bytes = try XCTUnwrap(pb.data(forType: .png))
        let expected = try Renderer.render(source: try Fixtures.source("small-dialog.png"), recipe: first)
        XCTAssertEqual(bytes, try PNG.encode(expected.image))
        model.undo()
        XCTAssertEqual(model.recipe, before)
        model.redo()
        XCTAssertEqual(model.recipe, first)
        model.randomizeGradient(using: &rng)
        strip.update(enabled: true)
        let latest = model.recipe
        model.toggleInspect()
        strip.update(enabled: true)
        XCTAssertFalse(model.gradientPresentationActive)
        XCTAssertEqual(strip.start.positionHue, Double(latest.gradientFrom))
        XCTAssertEqual(strip.end.positionHue, Double(latest.gradientTo))
        XCTAssertNil(model.presentationImage)
        XCTAssertEqual(model.recipe, latest)
        let resolved = await model.fullImage()
        let full = try XCTUnwrap(resolved)
        XCTAssertEqual(full.width, expected.image.width)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(model.recipe, latest, "A late presentation cannot restore the previous random pair")
        model.dismiss()
    }
    func testRandomizeHandleMotionCannotOutliveUndoOrKeyboardEditing() async throws {
        let model = try model()
        let strip = HueStripView(model: model)
        strip.update(enabled: true)
        let original = model.recipe
        var rng = Seeded(state: 17)
        model.randomizeGradient(using: &rng)
        strip.update(enabled: true)
        try await Task.sleep(for: .milliseconds(40))
        model.undo()
        strip.update(enabled: true)
        try await Task.sleep(for: .milliseconds(270))
        XCTAssertEqual(model.recipe, original)
        XCTAssertEqual(strip.start.positionHue, Double(original.gradientFrom))
        XCTAssertEqual(strip.end.positionHue, Double(original.gradientTo))

        model.randomizeGradient(using: &rng)
        strip.update(enabled: true)
        try await Task.sleep(for: .milliseconds(30))
        strip.keyboard(delta: 1, on: strip.start)
        strip.update(enabled: true)
        let edited = model.recipe
        try await Task.sleep(for: .milliseconds(270))
        XCTAssertEqual(strip.start.positionHue, Double(edited.gradientFrom))
        XCTAssertEqual(strip.end.positionHue, Double(edited.gradientTo))
        strip.endKeyboardBurst()
        model.dismiss()
    }
    func testSelfDragAndSafeCancelledTempCleanup() throws {
        let own = window()
        let external = window()
        let source = NSView()
        own.contentView?.addSubview(source)
        XCTAssertTrue(PanelMaterialView.isSelfDrag(source: source, window: own))
        XCTAssertFalse(PanelMaterialView.isSelfDrag(source: source, window: external))
        XCTAssertFalse(PanelMaterialView.isSelfDrag(source: nil, window: own))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let exported = try DragTempFiles.write(Data("temp".utf8), name: "export.png", directory: folder)
        let unrelated = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: unrelated) }
        try Data("user image".utf8).write(to: unrelated)
        DragTempFiles.remove(unrelated, directory: folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        DragTempFiles.remove(exported, directory: folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exported.path))
    }
    func testExplicitPanelSizesAndClickThroughShadowBounds() {
        let panel = FloatingPanel(size: PanelMetrics.card)
        let shadow = ShadowWindow()
        XCTAssertFalse(panel.isMovable)
        XCTAssertTrue(shadow.ignoresMouseEvents)
        for size in [
            PanelMetrics.card, NSSize(width: 844, height: 412), NSSize(width: 960, height: 608),
            PanelMetrics.card,
        ] {
            let rect = NSRect(origin: NSPoint(x: 12, y: 50), size: size)
            panel.setFrame(rect, display: false)
            shadow.place(around: panel.frame, weight: .light)
            XCTAssertEqual(panel.frame, rect)
            XCTAssertEqual(panel.contentView?.frame.size, size)
            XCTAssertEqual(shadow.frame, rect.insetBy(dx: -80, dy: -80))
        }
    }

    /// Draws the actual native controls for review. These are offscreen renders,
    /// not evidence of live material, focus delivery or window animation.
    func testWriteLightDarkFooterAndGradientWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["M12_CONTACT_DIR"] else { return }
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent()
        let model = try model()
        for dark in [false, true] {
            for enabled in [false, true] {
                let appearance = try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
                let image = NSImage(size: NSSize(width: 600, height: 90), flipped: false) { rect in
                    appearance.performAsCurrentDrawingAppearance {
                        NSColor(
                            srgbRed: dark ? 0.16 : 0.94, green: dark ? 0.16 : 0.94,
                            blue: dark ? 0.17 : 0.95, alpha: 1
                        ).setFill()
                        rect.fill()
                        @MainActor func draw(_ button: ActionButton, x: CGFloat, width: CGFloat) {
                            button.frame = NSRect(x: 0, y: 0, width: width, height: 38)
                            button.appearance = appearance
                            button.isEnabled = enabled
                            NSGraphicsContext.saveGraphicsState()
                            NSGraphicsContext.current?.cgContext.translateBy(x: x, y: 43)
                            button.draw(button.bounds)
                            NSGraphicsContext.restoreGraphicsState()
                        }
                        for (i, look) in LookID.allCases.enumerated() {
                            let button = ActionButton(model: model)
                            button.style = .swatch(look)
                            button.selected = look == .dawn
                            button.updateSwatch()
                            draw(button, x: 12 + CGFloat(i) * 40, width: 38)
                        }
                        for (title, x, width) in [
                            ("Adjust", CGFloat(346), CGFloat(64)), ("Save", 416, 54), ("Copy  ↵", 476, 106),
                        ] {
                            let button = ActionButton(model: model)
                            button.title = title
                            button.style = title.hasPrefix("Copy") ? .primary : .quiet
                            draw(button, x: x, width: width)
                        }
                        let strip = HueStripView(model: model)
                        strip.update(enabled: enabled)
                        NSGraphicsContext.saveGraphicsState()
                        NSGraphicsContext.current?.cgContext.translateBy(x: 12, y: 10)
                        strip.draw(strip.bounds)
                        for thumb in [strip.start, strip.end] {
                            NSGraphicsContext.saveGraphicsState()
                            NSGraphicsContext.current?.cgContext.translateBy(
                                x: thumb.frame.minX, y: thumb.frame.minY)
                            thumb.draw(thumb.bounds)
                            NSGraphicsContext.restoreGraphicsState()
                        }
                        NSGraphicsContext.restoreGraphicsState()
                    }
                    return true
                }
                let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
                try PNG.encode(cg).write(
                    to: folder.appendingPathComponent(
                        "footer-\(dark ? "dark" : "light")-\(enabled ? "ready" : "empty").png"))
            }
        }
        model.dismiss()
    }
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }
}
