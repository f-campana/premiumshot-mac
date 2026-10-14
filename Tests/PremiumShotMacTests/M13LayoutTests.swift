import AppKit
import PremiumShotCore
import SwiftUI
import XCTest

@testable import PremiumShotMac

@MainActor final class M13LayoutTests: XCTestCase {
    func testProductionControllerSettlesAtRequestedContentAndShadowBounds() async throws {
        let model = PanelModel(store: SessionStore())
        model.defaults = makeDefaults()
        model.pasteboard = makePasteboard()
        putFixture("wide-dashboard.png", on: model)
        defer { model.pasteboard.releaseGlobally() }
        let controller = PanelController(model: model)
        controller.show()
        defer { controller.hide() }
        for _ in 0..<300 where model.frame == nil { try await Task.sleep(for: .milliseconds(10)) }
        let panel = try XCTUnwrap(NSApp.windows.compactMap { $0 as? FloatingPanel }.first { $0.isVisible })
        let shadow = try XCTUnwrap(panel.childWindows?.compactMap { $0 as? ShadowWindow }.first)
        for state in ["compact", "expanded", "inspect", "expanded-return", "compact-return"] {
            switch state {
            case "expanded", "compact-return": model.toggleDrawer()
            case "inspect": model.toggleInspect()
            case "expanded-return": model.closeInspect()
            default: break
            }
            try await Task.sleep(for: .milliseconds(650))
            let area = try XCTUnwrap(panel.screen).visibleFrame
            let expected =
                state == "inspect"
                ? NSSize(width: min(960, area.width - 48), height: min(608, area.height - 48))
                : NSSize(width: model.isExpanded ? 844 : 600, height: 412)
            let content = try XCTUnwrap(panel.contentView)
            content.layoutSubtreeIfNeeded()
            XCTAssertEqual(panel.frame.size, expected, state)
            XCTAssertEqual(content.bounds.size, expected, state)
            XCTAssertEqual(shadow.frame, panel.frame.insetBy(dx: -80, dy: -80), state)
            print(
                "M13 production \(state) window=\(panel.frame) content=\(content.bounds) shadow=\(shadow.frame)"
            )
            if state == "inspect" {
                @MainActor func canvas(in view: NSView) -> InspectCanvas? {
                    if let found = view as? InspectCanvas { return found }
                    return view.subviews.lazy.compactMap { canvas(in: $0) }.first
                }
                let inspect = try XCTUnwrap(canvas(in: content))
                let rect = content.convert(inspect.bounds, from: inspect)
                let bottom = content.isFlipped ? expected.height - rect.maxY : rect.minY
                print("M13 production inspect well=\(rect) bottom=\(bottom)")
                XCTAssertEqual(rect.height, expected.height - 64, accuracy: 0.01)
                XCTAssertEqual(bottom, 12, accuracy: 0.01)
            }
        }
        controller.hide()
        controller.show()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(panel.frame.size, PanelMetrics.card)
        XCTAssertEqual(shadow.frame, panel.frame.insetBy(dx: -80, dy: -80))
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(panel.frame.size, PanelMetrics.card)
        XCTAssertEqual(shadow.frame, panel.frame.insetBy(dx: -80, dy: -80))
    }

    func testHostedInspectWindowAndWellMatchRequestedBounds() async throws {
        let model = PanelModel(store: SessionStore())
        model.defaults = makeDefaults()
        model.replace(with: try Fixtures.source("wide-dashboard.png"))
        for _ in 0..<300 where model.frame == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(model.frame)
        let panel = FloatingPanel(size: PanelMetrics.card)
        let host = NSHostingView(rootView: PanelView(model: model))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        let background = NSView(frame: NSRect(origin: .zero, size: PanelMetrics.card))
        background.wantsLayer = true
        background.addSubview(host)
        panel.contentView = background
        defer {
            panel.contentView = nil
            model.dismiss()
        }
        @MainActor func canvas(in view: NSView) -> InspectCanvas? {
            if let found = view as? InspectCanvas { return found }
            return view.subviews.lazy.compactMap { canvas(in: $0) }.first
        }
        let folder = ProcessInfo.processInfo.environment["M13_EVIDENCE_DIR"].map {
            URL(fileURLWithPath: $0)
        }
        for dark in [false, true] {
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            background.layer?.backgroundColor =
                NSColor(
                    srgbRed: dark ? 0.16 : 0.94, green: dark ? 0.16 : 0.94,
                    blue: dark ? 0.17 : 0.95, alpha: 1
                ).cgColor
            for size in [NSSize(width: 960, height: 608), NSSize(width: 820, height: 500)] {
                model.toggleInspect()
                panel.setContentSize(size)
                host.frame = NSRect(origin: .zero, size: size)
                for _ in 0..<30 {
                    host.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(10))
                }
                let inspect = try XCTUnwrap(canvas(in: host))
                let rect = host.convert(inspect.bounds, from: inspect)
                let bottom = host.isFlipped ? size.height - rect.maxY : rect.minY
                print(
                    "M13 \(dark ? "dark" : "light") window=\(panel.frame.size) host=\(host.frame.size) well=\(rect) bottom=\(bottom)"
                )
                XCTAssertEqual(panel.frame.size, size)
                XCTAssertEqual(host.frame.size, size)
                XCTAssertEqual(rect.width, size.width - 24, accuracy: 0.01)
                XCTAssertEqual(rect.height, size.height - 64, accuracy: 0.01)
                XCTAssertEqual(bottom, 12, accuracy: 0.01)
                if let folder, let bitmap = background.bitmapImageRepForCachingDisplay(in: background.bounds)
                {
                    background.cacheDisplay(in: background.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                        to: folder.appendingPathComponent(
                            "inspect-\(dark ? "dark" : "light")-\(Int(size.width))x\(Int(size.height)).png"))
                }
                model.closeInspect()
            }
        }
    }

    func testWellTreatmentsKeepGeometryAndWriteComparison() async throws {
        let model = PanelModel(store: SessionStore())
        model.defaults = makeDefaults()
        model.replace(with: try Fixtures.source("small-dialog.png"))
        for _ in 0..<300 where model.frame == nil { try await Task.sleep(for: .milliseconds(10)) }
        model.focus = .preview
        model.toggleDrawer()
        let size = NSSize(width: 844, height: 412)
        let panel = FloatingPanel(size: size)
        let host = NSHostingView(rootView: PanelView(model: model))
        host.sizingOptions = []
        let background = NSView(frame: NSRect(origin: .zero, size: size))
        background.wantsLayer = true
        host.frame = background.bounds
        background.addSubview(host)
        panel.contentView = background
        defer {
            panel.contentView = nil
            model.dismiss()
        }
        @MainActor func preview(_ view: NSView) -> PreviewCanvas? {
            if let found = view as? PreviewCanvas { return found }
            return view.subviews.lazy.compactMap { preview($0) }.first
        }
        for dark in [false, true] {
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            background.layer?.backgroundColor =
                NSColor(
                    srgbRed: dark ? 0.16 : 0.94, green: dark ? 0.16 : 0.94,
                    blue: dark ? 0.17 : 0.95, alpha: 1
                ).cgColor
            for tone in WellTone.allCases {
                host.rootView = PanelView(model: model, wellTone: tone)
                for _ in 0..<15 {
                    host.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(10))
                }
                let canvas = try XCTUnwrap(preview(host))
                XCTAssertEqual(canvas.bounds.size, PanelMetrics.well)
                if let path = ProcessInfo.processInfo.environment["M13_EVIDENCE_DIR"],
                    let bitmap = background.bitmapImageRepForCachingDisplay(in: background.bounds)
                {
                    background.cacheDisplay(in: background.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                        to: URL(fileURLWithPath: path).appendingPathComponent(
                            "well-\(dark ? "dark" : "light")-\(tone.rawValue).png"))
                }
            }
        }
    }
}
