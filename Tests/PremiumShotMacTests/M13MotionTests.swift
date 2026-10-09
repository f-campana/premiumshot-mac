import AppKit
import PremiumShotCore
import SwiftUI
import XCTest

@testable import PremiumShotMac

@MainActor final class M13MotionTests: XCTestCase {
    func testIrregularClockEndsExactlyAndReversalPreservesVelocity() {
        let compact = PanelPose(card: CGRect(x: 100, y: 100, width: 600, height: 412))
        let expanded = PanelPose(card: CGRect(x: 100, y: 100, width: 844, height: 412), drawer: 1)
        var timeline = PanelTimeline(from: compact, to: expanded, duration: 0.28)
        var previous = 0.0
        for time in [0.0, 0.008, 0.016, 0.049, 0.091, 0.17, 0.24, 0.28, 0.4] {
            let p = timeline.progress(at: time).value
            XCTAssertGreaterThanOrEqual(p, previous)
            XCTAssertLessThanOrEqual(p, 1)
            previous = p
        }
        XCTAssertEqual(timeline.pose(at: 0.28).card, expanded.card)
        let position = timeline.pose(at: 0.07)
        let velocity = timeline.velocity(at: 0.07)
        timeline.retarget(compact, duration: 0.22, at: 0.07)
        XCTAssertEqual(timeline.pose(at: 0).card, position.card)
        for (before, after) in zip(velocity, timeline.velocity(at: 0)) {
            XCTAssertEqual(before, after, accuracy: 0.00001)
        }
        // Signed velocity continues briefly in the previous direction while decelerating.
        XCTAssertGreaterThan(timeline.pose(at: 0.001).card.width, position.card.width)
        XCTAssertEqual(timeline.pose(at: 0.22).card, compact.card)
        timeline.retarget(expanded, duration: 0.28, at: 0.03)
        XCTAssertEqual(timeline.pose(at: 1).card, expanded.card)
        let inspect = PanelPose(card: CGRect(x: 60, y: 70, width: 960, height: 608))
        let mixedPosition = timeline.pose(at: 0.06)
        let mixedVelocity = timeline.velocity(at: 0.06)
        timeline.retarget(inspect, duration: 0.32, at: 0.06)
        XCTAssertEqual(timeline.pose(at: 0).card, mixedPosition.card)
        for (before, after) in zip(mixedVelocity, timeline.velocity(at: 0)) {
            XCTAssertEqual(before, after, accuracy: 0.00001)
        }
        XCTAssertEqual(timeline.pose(at: 0.32).card, inspect.card)
    }

    func testReduceMotionAndSnapProduceOnlyTargetFrames() {
        let window = FloatingPanel(size: PanelMetrics.card)
        let state = PanelPresentation()
        var frames: [CGRect] = []
        let animator = PanelAnimator(window: window, state: state, reducesMotion: { true }) {
            frames.append($0.card)
        }
        let target = PanelPose(card: CGRect(x: 100, y: 100, width: 960, height: 608), compact: 0, inspect: 1)
        animator.begin(target, mode: .inspect, duration: 0.32, sharedImage: true)
        XCTAssertEqual(frames, [target.card])
        XCTAssertFalse(state.active)
        XCTAssertFalse(state.sharedImage)
        XCTAssertEqual(state.inspectOpacity, 1)
        var movingFrames: [CGRect] = []
        let moving = PanelAnimator(window: window, state: state, reducesMotion: { false }) {
            movingFrames.append($0.card)
        }
        moving.begin(target, mode: .inspect, duration: 0.32, sharedImage: true)
        moving.snap()
        XCTAssertEqual(movingFrames.last, target.card)
        XCTAssertFalse(state.active)
    }

    func testProductionAdjustKeepsCompactControlsStillAndOutputSnaps() async throws {
        let model = PanelModel(store: SessionStore())
        model.defaults = makeDefaults()
        model.demoImageURL = Fixtures.url("wide-dashboard.png")
        model.pasteboard = makePasteboard()
        defer { model.pasteboard.releaseGlobally() }
        let controller = PanelController(model: model)
        controller.show()
        defer { controller.hide() }
        for _ in 0..<300 where model.frame == nil { try await Task.sleep(for: .milliseconds(10)) }
        let panel = try XCTUnwrap(NSApp.windows.compactMap { $0 as? FloatingPanel }.first { $0.isVisible })
        let root = try XCTUnwrap(panel.contentView)
        @MainActor func controls(_ view: NSView) -> [ActionButton] {
            (view as? ActionButton).map { [$0] } ?? view.subviews.flatMap(controls)
        }
        root.layoutSubtreeIfNeeded()
        let original = Dictionary(
            uniqueKeysWithValues: controls(root).compactMap { button -> (String, CGRect)? in
                guard let id = button.identifier?.rawValue else { return nil }
                return (id, root.convert(button.bounds, from: button))
            })
        for _ in 0..<2 {
            model.toggleDrawer()
            for _ in 0..<35 {
                root.layoutSubtreeIfNeeded()
                for button in controls(root) {
                    guard let id = button.identifier?.rawValue, let before = original[id] else { continue }
                    XCTAssertEqual(root.convert(button.bounds, from: button), before, id)
                }
                if let shadow = panel.childWindows?.compactMap({ $0 as? ShadowWindow }).first {
                    XCTAssertEqual(shadow.frame, panel.frame.insetBy(dx: -80, dy: -80))
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        model.toggleDrawer()
        await model.copy()
        XCTAssertEqual(panel.frame.width, 844, "Copy must snap the active drawer transition")
        XCTAssertEqual(model.pasteboard.types?.contains(.png), true)
        model.toggleInspect()
        model.closeInspect()
        model.toggleInspect()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(panel.frame.size, NSSize(width: 960, height: 608))
        XCTAssertTrue(model.isInspecting)
    }

    func testHueTargetsAndInformationalContrast() throws {
        let model = PanelModel(store: SessionStore())
        model.defaults = makeDefaults()
        let strip = HueStripView(model: model)
        strip.update(enabled: true)
        XCTAssertEqual(strip.start.bounds.size, NSSize(width: 28, height: 28))
        let point = NSPoint(x: strip.start.frame.midX + 12, y: strip.start.frame.midY)
        XCTAssertTrue(
            strip.hitTest(point) === strip.start, "The target extends beyond the 18 pt visible circle")
        for dark in [false, true] {
            let appearance = try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
            appearance.performAsCurrentDrawingAppearance {
                let ink = PanelTheme.information.usingColorSpace(.sRGB)!
                func linear(_ v: Double) -> Double {
                    v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
                }
                func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
                    0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
                }
                let foreground = luminance(ink.redComponent, ink.greenComponent, ink.blueComponent)
                let background = luminance(dark ? 0.16 : 0.94, dark ? 0.16 : 0.94, dark ? 0.17 : 0.95)
                let contrast = (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
                XCTAssertGreaterThanOrEqual(contrast, 4.5)
                print(
                    "M13 informational contrast \(dark ? "dark" : "light") \(contrast):1 against the flat QA backdrop"
                )
            }
        }
    }

    func testKeyboardDrawerReversalAndInspectEntryKeepCurrentWindowPose() async throws {
        try XCTSkipIf(
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "With Reduce Motion, switching directly to the target is intentional")
        let model = PanelModel(store: SessionStore())
        model.defaults = makeDefaults()
        model.demoImageURL = Fixtures.url("wide-dashboard.png")
        model.pasteboard = makePasteboard()
        defer { model.pasteboard.releaseGlobally() }
        let controller = PanelController(model: model)
        controller.show()
        defer { controller.hide() }
        for _ in 0..<300 where model.frame == nil { try await Task.sleep(for: .milliseconds(10)) }
        let panel = try XCTUnwrap(NSApp.windows.compactMap { $0 as? FloatingPanel }.first { $0.isVisible })
        let shadow = try XCTUnwrap(panel.childWindows?.compactMap { $0 as? ShadowWindow }.first)
        try await Task.sleep(for: .milliseconds(350))

        func key(_ characters: String, code: UInt16) throws -> NSEvent {
            try XCTUnwrap(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: panel.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        }
        func awaitPartialDrawer() async throws {
            for _ in 0..<100 {
                if panel.frame.width > 610 && panel.frame.width < 840 { return }
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTFail("The display link must present a partial drawer before retargeting")
        }
        @MainActor func preview(in view: NSView) -> PreviewCanvas? {
            if let found = view as? PreviewCanvas { return found }
            return view.subviews.lazy.compactMap { preview(in: $0) }.first
        }

        let e = try key("e", code: 14)
        XCTAssertTrue(controller.handle(e))
        try await awaitPartialDrawer()
        let reversingCard = panel.frame
        let reversingShadow = shadow.frame
        XCTAssertTrue(controller.handle(e))
        XCTAssertEqual(panel.frame, reversingCard, "A second E must retarget without snapping first")
        XCTAssertEqual(shadow.frame, reversingShadow)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(panel.frame.size, PanelMetrics.card)
        XCTAssertFalse(model.isExpanded)

        XCTAssertTrue(controller.handle(e))
        try await awaitPartialDrawer()
        let canvas = try XCTUnwrap(preview(in: try XCTUnwrap(panel.contentView)))
        XCTAssertTrue(panel.makeFirstResponder(canvas))
        model.focus = .preview
        let inspectingCard = panel.frame
        let inspectingShadow = shadow.frame
        XCTAssertTrue(controller.handle(try key(" ", code: 49)))
        XCTAssertTrue(model.isInspecting)
        XCTAssertEqual(panel.frame, inspectingCard, "Space during Adjust must keep the current pose")
        XCTAssertEqual(shadow.frame, inspectingShadow)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(panel.frame.size, NSSize(width: 960, height: 608))
        XCTAssertEqual(shadow.frame, panel.frame.insetBy(dx: -80, dy: -80))
    }
}
