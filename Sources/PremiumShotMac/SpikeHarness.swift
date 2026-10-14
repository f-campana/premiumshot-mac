#if DEBUG
import AppKit
import PremiumShotCore

/// Dev-only windows for the two spike checks that need a human: drag-out (S8) and swipe direction (S10).
@MainActor
public final class SpikeHarness {
    public static let shared = SpikeHarness()
    private var dragWindow: NSWindow?, gestureWindow: NSWindow?

    public func showDragTest() {
        if dragWindow == nil {
            dragWindow = Self.window(
                title: "Spike S8: drag-out", size: NSSize(width: 520, height: 300), content: DragSourceView())
        }
        show(dragWindow!)
    }
    public func showGestureLogger() {
        if gestureWindow == nil {
            gestureWindow = Self.window(
                title: "Spike S10: swipe direction", size: NSSize(width: 620, height: 420),
                content: GestureLoggerView())
        }
        show(gestureWindow!)
    }
    private func show(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
    private static func window(title: String, size: NSSize, content: NSView) -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        w.title = title
        w.contentView = content
        w.center()
        w.isReleasedWhenClosed = false
        return w
    }
}

/// A view you drag from. It renders a real polished PNG into the temp directory and drags that file, so you can
/// drop it into Finder, Slack and a browser upload zone.
final class DragSourceView: NSView, NSDraggingSource {
    private let label = NSTextField(wrappingLabelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 13)
        label.frame = NSRect(x: 24, y: 24, width: 472, height: 90)
        label.autoresizingMask = [.width]
        label.stringValue =
            "Drag the card above into Finder, Slack and a browser upload zone.\nEach drop should receive a valid PNG of the resolved size (1200 × 630 plus margins)."
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let card = NSRect(x: 24, y: 130, width: bounds.width - 48, height: bounds.height - 154)
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: card, xRadius: 16, yRadius: 16).fill()
        let text = NSAttributedString(
            string: "Drag me",
            attributes: [
                .font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor.labelColor,
            ])
        text.draw(at: NSPoint(x: card.midX - text.size().width / 2, y: card.midY - text.size().height / 2))
    }

    override func mouseDown(with event: NSEvent) {
        do {
            let image = Self.testImage()
            let result = try Renderer.render(source: SourceImage(cgImage: image), recipe: .default)
            let url = try DragTempFiles.write(try PNG.encode(result.image), name: "PremiumShot drag test.png")
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let thumb = NSImage(
                cgImage: result.image,
                size: NSSize(
                    width: 160, height: 160 * CGFloat(result.image.height) / CGFloat(result.image.width)))
            item.setDraggingFrame(
                NSRect(
                    x: event.locationInWindow.x - 80, y: event.locationInWindow.y - 40,
                    width: thumb.size.width, height: thumb.size.height), contents: thumb)
            beginDraggingSession(with: [item], event: event, source: self)
            label.stringValue =
                "Dragging \(url.lastPathComponent) (\(result.layout.width) × \(result.layout.height) px)."
        } catch { label.stringValue = "Drag did not start: \(error.localizedDescription)" }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation
    { .copy }
    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        label.stringValue +=
            operation.isEmpty
            ? "\nDrop was refused or cancelled." : "\nDrop was accepted (operation \(operation.rawValue))."
    }

    private static func testImage() -> CGImage {
        let w = 1200
        let h = 630
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        let gradient = CGGradient(
            colorsSpace: space,
            colors: [
                CGColor(srgbRed: 0.18, green: 0.42, blue: 1, alpha: 1),
                CGColor(srgbRed: 0.65, green: 0.42, blue: 1, alpha: 1),
            ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: w, y: h), options: [])
        return ctx.makeImage()!
    }
}

/// Shows every scroll and pinch event with its direction flags, and applies the spec's rule:
/// two fingers up zoom in, two fingers down zoom out, whatever the system scrolling direction.
final class GestureLoggerView: NSView {
    private let log = NSTextField(labelWithString: "")
    private var zoom = 1.0
    private var lines: [String] = []
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        log.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        log.maximumNumberOfLines = 0
        log.frame = NSRect(x: 16, y: 16, width: 588, height: 388)
        log.autoresizingMask = [.width, .height]
        log.alignment = .left
        addSubview(log)
        refresh(
            header:
                "Scroll with two fingers over this window. Try natural scrolling on and off in System Settings."
        )
    }
    required init?(coder: NSCoder) { fatalError() }

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }
        let dy = Double(event.scrollingDeltaY)
        let inverted = event.isDirectionInvertedFromDevice
        guard let intent = Gestures.zoomIntent(scrollingDeltaY: dy, directionInvertedFromDevice: inverted)
        else { return }
        zoom = min(4, max(0.1, zoom * exp((intent == .zoomIn ? 1 : -1) * min(abs(dy), 40) * 0.006)))
        let fingers = Gestures.fingerDirection(scrollingDeltaY: dy, directionInvertedFromDevice: inverted)!
        push(
            String(
                format: "scroll dy %+7.2f  natural:%@  fingers:%@  -> %@   zoom %3.0f%%", dy,
                inverted ? "on " : "off", fingers == .up ? "up  " : "down",
                intent == .zoomIn ? "ZOOM IN " : "ZOOM OUT", zoom * 100))
    }
    override func magnify(with event: NSEvent) {
        zoom = min(4, max(0.1, zoom * (1 + Double(event.magnification))))
        push(String(format: "pinch %+.3f  -> zoom %3.0f%%", Double(event.magnification), zoom * 100))
    }
    private func push(_ line: String) {
        lines.append(line)
        if lines.count > 22 { lines.removeFirst() }
        refresh(header: "fingers up should always ZOOM IN, fingers down ZOOM OUT")
    }
    private func refresh(header: String) { log.stringValue = ([header, ""] + lines).joined(separator: "\n") }
}

#endif
