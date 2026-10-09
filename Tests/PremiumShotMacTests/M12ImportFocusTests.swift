import AppKit
import PremiumShotCore
import XCTest

@testable import PremiumShotMac

@MainActor final class M12ImportFocusTests: XCTestCase {
    private func item(_ file: URL, icon: Data) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(file.absoluteString, forType: .fileURL)
        item.setData(icon, forType: .tiff)
        return item
    }

    func testFileFailuresNeverImportAccompanyingIconsAndRespectEligibility() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let corrupt = folder.appendingPathComponent("corrupt.png")
        let text = folder.appendingPathComponent("notes.txt")
        let pdf = folder.appendingPathComponent("document.pdf")
        let gif = folder.appendingPathComponent("unsupported.gif")
        try Data("broken".utf8).write(to: corrupt)
        try Data("notes".utf8).write(to: text)
        try Data("%PDF-1.7".utf8).write(to: pdf)
        // A real GIF signature, sufficient for ImageIO to identify the unsupported type.
        try Data([
            71, 73, 70, 56, 57, 97, 1, 0, 1, 0, 128, 0, 0, 0, 0, 0, 255, 255, 255, 44, 0, 0, 0, 0, 1, 0, 1, 0,
            0, 2, 2, 68, 1, 0, 59,
        ]).write(to: gif)
        let oversized = folder.appendingPathComponent("oversized.png")
        let side = 8200
        let row = (side + 7) / 8
        let provider = try XCTUnwrap(CGDataProvider(data: Data(count: row * side) as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: side, height: side, bitsPerComponent: 1,
                bitsPerPixel: 1, bytesPerRow: row, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        try PNG.encode(image).write(to: oversized)
        let icon = try Fixtures.tiffData("thin-strip.png")
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        for (file, eligible) in [
            (corrupt, true), (text, false), (pdf, false), (gif, false), (folder, false), (oversized, true),
        ] {
            pb.clearContents()
            XCTAssertTrue(pb.writeObjects([item(file, icon: icon)]))
            let payload = ImageImportPayload(pb)
            XCTAssertEqual(payload.files, [file])
            XCTAssertTrue(payload.images.isEmpty, "File icons are not captured")
            XCTAssertThrowsError(try payload.decode(), file.lastPathComponent)
            guard case .none(let reason) = PasteboardIO.read(from: pb) else {
                XCTFail("Imported icon for \(file.lastPathComponent)")
                continue
            }
            XCTAssertNotNil(reason)
            XCTAssertEqual(PanelMaterialView.eligible(pb), eligible, file.lastPathComponent)
        }
    }

    func testInvalidThenValidFileAndImageOnlyTIFF() throws {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let icon = try Fixtures.tiffData("thin-strip.png")
        XCTAssertTrue(
            pb.writeObjects([
                item(URL(fileURLWithPath: "/no-such-image.png"), icon: icon),
                item(Fixtures.url("small-dialog.png"), icon: icon),
            ]))
        guard case .image(let source, _) = PasteboardIO.read(from: pb) else {
            return XCTFail("valid second file")
        }
        XCTAssertEqual(source.width, 880)
        XCTAssertTrue(PanelMaterialView.eligible(pb))
        pb.clearContents()
        pb.setData(icon, forType: .tiff)
        guard case .image(let dataOnly, _) = PasteboardIO.read(from: pb) else {
            return XCTFail("image-only TIFF")
        }
        XCTAssertEqual(dataOnly.width, try Fixtures.source("thin-strip.png").width)
    }

    func testFailedPastePreservesReadyAndReportsErrorInEmpty() async throws {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let model = PanelModel(store: SessionStore())
        model.pasteboard = pb
        model.defaults = makeDefaults()
        model.replace(with: try Fixtures.source("small-dialog.png"))
        for _ in 0..<200 where model.frame == nil { try await Task.sleep(for: .milliseconds(10)) }
        let frame = try XCTUnwrap(model.frame)
        let source = model.currentSession?.source
        XCTAssertTrue(
            pb.writeObjects([
                item(URL(fileURLWithPath: "/missing.png"), icon: try Fixtures.tiffData("thin-strip.png"))
            ]))
        let count = pb.changeCount
        model.paste()
        XCTAssertTrue(model.isReady)
        XCTAssertTrue(model.currentSession?.source === source)
        XCTAssertEqual(model.frame?.token, frame.token)
        XCTAssertEqual(model.recipe, frame.recipe)
        guard case .error = model.status else { return XCTFail("file error in Ready") }
        XCTAssertEqual(pb.changeCount, count)
        model.removeScreenshot()
        model.paste()
        guard case .empty(let reason) = model.phase else { return XCTFail("Empty preserved") }
        XCTAssertNotNil(reason)
        XCTAssertFalse(model.isReady)
        XCTAssertEqual(pb.changeCount, count)
    }

    func testInspectAttachmentTransfersFocusOnceAndKeyboardWorksImmediately() async throws {
        let model = PanelModel(store: SessionStore())
        model.defaults = makeDefaults()
        model.replace(with: try Fixtures.source("wide-dashboard.png"))
        for _ in 0..<200 where model.frame == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(model.frame)
        model.toggleInspect()
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let root = NSView(frame: window.contentView!.bounds)
        window.contentView = root
        let other = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        root.addSubview(other)
        window.makeFirstResponder(other)
        let canvas = InspectCanvas(model: model)
        canvas.frame = root.bounds
        canvas.refresh(command: .fit, commandID: 0)
        root.addSubview(canvas)
        for _ in 0..<100 where window.firstResponder !== canvas { await Task.yield() }
        XCTAssertTrue(window.firstResponder === canvas)
        let z = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "z",
                charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6))
        window.firstResponder?.keyDown(with: z)
        XCTAssertEqual(canvas.zoom.scale, 1)
        window.makeFirstResponder(other)
        let responder = window.firstResponder
        canvas.refresh(command: .actual, commandID: 1)
        await Task.yield()
        XCTAssertTrue(window.firstResponder === responder, "Refresh must not steal focus from a control")
        canvas.removeFromSuperview()
        let late = InspectCanvas(model: model)
        root.addSubview(late)
        model.closeInspect()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(window.firstResponder === late, "A closed Inspect must not receive late focus")
    }
}
