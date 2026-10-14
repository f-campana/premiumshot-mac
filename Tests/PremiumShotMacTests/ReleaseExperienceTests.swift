import AppKit
import PremiumShotCore
import SwiftUI
import XCTest

@testable import PremiumShotMac

@MainActor final class ReleaseExperienceTests: XCTestCase {
    func testDeveloperDragCleanupCannotTouchTheProductionCache() {
        let production = DragTempFiles.directory(bundleIdentifier: "app.premiumshot.mac")
        let development = DragTempFiles.directory(bundleIdentifier: "app.premiumshot.mac.dev")
        XCTAssertNotEqual(production, development)
        XCTAssertEqual(production.deletingLastPathComponent().lastPathComponent, "app.premiumshot.mac")
        XCTAssertEqual(development.deletingLastPathComponent().lastPathComponent, "app.premiumshot.mac.dev")
    }

    func testWelcomeDoesNotReadClipboardOrFolderAndOnlyStartCompletesIt() throws {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let original = try Fixtures.data("small-dialog.png")
        pb.setData(original, forType: .png)
        let count = pb.changeCount
        let model = PanelModel(store: SessionStore())
        model.defaults = makeDefaults()
        model.pasteboard = pb
        model.findLatestScreenshot = { _ in XCTFail("Welcome must not enumerate the folder"); return nil }
        XCTAssertTrue(FirstLaunch.needsWelcome(in: model.defaults))
        model.showWelcome()
        XCTAssertTrue(model.isWelcoming)
        XCTAssertNil(model.currentSession)
        XCTAssertEqual(pb.changeCount, count)
        XCTAssertEqual(pb.data(forType: .png), original)
        model.dismiss()
        XCTAssertTrue(FirstLaunch.needsWelcome(in: model.defaults))
        model.showWelcome()
        var completed = false
        model.onFinishWelcome = { completed = true }
        model.finishWelcome()
        XCTAssertTrue(completed)
        XCTAssertFalse(model.isWelcoming)
        XCTAssertFalse(FirstLaunch.needsWelcome(in: model.defaults))
        // Reopening Welcome never changes the clipboard or undoes completion.
        model.showWelcome()
        XCTAssertEqual(pb.changeCount, count)
        XCTAssertFalse(FirstLaunch.needsWelcome(in: model.defaults))
        model.dismiss()
    }

    func testStartDismissesTheRealWelcomePanel() {
        let model = PanelModel(store: SessionStore())
        model.defaults = makeDefaults()
        model.pasteboard = makePasteboard()
        defer { model.pasteboard.releaseGlobally() }
        let controller = PanelController(model: model)
        controller.showWelcome()
        XCTAssertTrue(controller.isVisible)
        model.finishWelcome()
        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(FirstLaunch.needsWelcome(in: model.defaults))
    }

    func testWelcomeCheckboxIsReachableAndReflectsRegistrationFailure() async throws {
        var registrations = 0
        let login = LoginItemController(status: { .off }, register: {
            registrations += 1
            throw CocoaError(.fileWriteNoPermission)
        }, unregister: {})
        let model = PanelModel(store: SessionStore(), loginItems: login)
        model.defaults = makeDefaults()
        model.showWelcome()
        let host = NSHostingView(rootView: PanelView(model: model))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: PanelMetrics.card)
        for _ in 0..<10 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10)) }
        func find(_ view: NSView) -> NSButton? {
            if view.identifier?.rawValue == "ps.welcome-login" { return view as? NSButton }
            return view.subviews.lazy.compactMap(find).first
        }
        let checkbox = try XCTUnwrap(find(host))
        XCTAssertEqual(checkbox.accessibilityRole(), .checkBox)
        XCTAssertTrue(checkbox.canBecomeKeyView)
        XCTAssertEqual(checkbox.state, .off)
        checkbox.performClick(nil)
        XCTAssertEqual(registrations, 1)
        XCTAssertEqual(checkbox.state, .off, "A failed registration must leave the actual checkbox unchecked")
        XCTAssertNotNil(login.message)
        model.dismiss()
    }

    func testLoginItemUsesSystemStateAfterApprovalFailureAndExternalChanges() {
        var system: LoginItemController.State = .off
        var registrations = 0
        let login = LoginItemController(status: { system }, register: {
            registrations += 1
            system = .needsApproval
        }, unregister: { system = .off })
        XCTAssertFalse(login.isRequested)
        login.setEnabled(true)
        XCTAssertEqual(registrations, 1)
        XCTAssertEqual(login.state, .needsApproval)
        XCTAssertTrue(login.isRequested)
        XCTAssertNotNil(login.message)
        login.setEnabled(true)
        XCTAssertEqual(registrations, 1)
        system = .on
        login.refresh()
        XCTAssertTrue(login.isRequested)
        XCTAssertNil(login.message)
        login.setEnabled(false)
        XCTAssertFalse(login.isRequested)
        let failed = LoginItemController(status: { .off }, register: {
            throw CocoaError(.fileWriteNoPermission)
        }, unregister: {})
        failed.setEnabled(true)
        XCTAssertFalse(failed.isRequested, "A failed registration must never leave a checked box")
        XCTAssertNotNil(failed.message)
    }

    func testDeniedFolderLeavesPasteCopyAndExistingSourceUsable() async throws {
        let model = PanelModel(store: SessionStore())
        model.defaults = makeDefaults()
        model.pasteboard = makePasteboard()
        defer { model.pasteboard.releaseGlobally() }
        model.findLatestScreenshot = { _ in throw CocoaError(.fileReadNoPermission) }
        model.openLatest()
        for _ in 0..<100 where !model.needsScreenshotFolder { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.phase, .empty("PremiumShot can't read your screenshots folder."))
        XCTAssertTrue(model.needsScreenshotFolder)
        putFixture("small-dialog.png", on: model)
        model.paste()
        for _ in 0..<200 where !model.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let session = try XCTUnwrap(model.currentSession)
        await model.copy()
        XCTAssertNotNil(model.pasteboard.data(forType: .png))
        XCTAssertEqual(PasteboardIO.marker(on: model.pasteboard), session.id)
        model.openLatest()
        for _ in 0..<100 where !model.needsScreenshotFolder { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.currentSession?.id, session.id)
        XCTAssertTrue(model.isReady)
        model.dismiss()
    }

    func testLatestDecodesWithinFolderAccessAndDiscardsLateResultAfterDismiss() async throws {
        let model = PanelModel(store: SessionStore())
        model.defaults = makeDefaults()
        let fixture = Fixtures.url("thin-strip.png")
        model.findLatestScreenshot = { _ in fixture }
        model.openLatest()
        for _ in 0..<100 where !model.isReady { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.isReady)
        XCTAssertEqual(model.currentSession?.source.width, try Fixtures.source("thin-strip.png").width)
        model.findLatestScreenshot = { _ in
            Thread.sleep(forTimeInterval: 0.05)
            return fixture
        }
        model.openLatest()
        model.dismiss()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(model.isReady)
        XCTAssertNil(model.currentSession)
    }

    func testSelectedFolderBookmarkAndNestedPermissionErrors() throws {
        let defaults = makeDefaults()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try ScreenshotFolder.remember(folder, in: defaults)
        XCTAssertEqual(try ScreenshotFolder.selected(in: defaults).standardizedFileURL, folder.standardizedFileURL)
        let nested = NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))])
        XCTAssertTrue(ScreenshotFolder.isDenied(nested))
        XCTAssertFalse(ScreenshotFolder.isDenied(CocoaError(.fileReadCorruptFile)))
    }

    func testWelcomeAndDeniedRecoveryFitTheCompactCardInBothAppearances() async throws {
        let model = PanelModel(store: SessionStore())
        model.defaults = makeDefaults()
        model.pasteboard = makePasteboard()
        defer { model.pasteboard.releaseGlobally() }
        let size = PanelMetrics.card
        let host = NSHostingView(rootView: PanelView(model: model))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        let backdrop = NSView(frame: host.frame)
        backdrop.wantsLayer = true
        backdrop.addSubview(host)
        let folder = ProcessInfo.processInfo.environment["RELEASE_EVIDENCE_DIR"].map { URL(fileURLWithPath: $0) }
        for dark in [false, true] {
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            backdrop.layer?.backgroundColor = NSColor(white: dark ? 0.16 : 0.94, alpha: 1).cgColor
            for state in ["welcome", "shortcut-conflict", "folder-denied"] {
                if state == "folder-denied" {
                    model.summon()
                    model.findLatestScreenshot = { _ in throw CocoaError(.fileReadNoPermission) }
                    model.openLatest()
                    for _ in 0..<100 where !model.needsScreenshotFolder { try await Task.sleep(for: .milliseconds(10)) }
                } else {
                    model.hotkeyUnavailable = state == "shortcut-conflict"
                    model.showWelcome()
                }
                for _ in 0..<10 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10)) }
                XCTAssertEqual(host.bounds.size, size)
                XCTAssertLessThanOrEqual(host.fittingSize.height, size.height)
                if let folder, let bitmap = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds) {
                    backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                        to: folder.appendingPathComponent("\(state)-\(dark ? "dark" : "light").png"))
                }
            }
        }
        model.dismiss()
    }
}
