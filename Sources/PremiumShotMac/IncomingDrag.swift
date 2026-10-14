import AppKit
import PremiumShotCore
import UniformTypeIdentifiers

/// Decision state only. The controller supplies live drag eligibility and physical button state.
struct OutsideGesture {
    enum Phase: Equatable { case idle, pressed, unknown, eligible, ineligible }
    private(set) var phase: Phase = .idle
    private var origin = CGPoint.zero
    private(set) var pasteboardCount = 0
    mutating func press(at point: CGPoint, pasteboardCount: Int) {
        origin = point
        self.pasteboardCount = pasteboardCount
        phase = .pressed
    }
    mutating func move(to point: CGPoint) {
        if phase == .pressed && hypot(point.x - origin.x, point.y - origin.y) >= 4 { phase = .unknown }
    }
    mutating func classify(eligible: Bool) {
        guard phase != .idle else { return }
        phase = eligible ? .eligible : .ineligible
    }
    mutating func end(buttonStillDown: Bool = false) -> Bool {
        guard !buttonStillDown else { return false }
        let dismiss = phase != .idle && phase != .eligible
        phase = .idle
        return dismiss
    }
    mutating func cancel() { phase = .idle }
}

/// A parent destination covers the image and caption without stealing a drop.
final class PanelMaterialView: NSVisualEffectView {
    typealias PromiseDelivery = (NSFilePromiseReceiver, URL, @escaping (URL, Error?) -> Void) -> Void
    let model: PanelModel
    private let deliverPromise: PromiseDelivery
    var onDragEligibility: ((Bool) -> Void)?
    var onDragEnd: (() -> Void)?
    static var types: [NSPasteboard.PasteboardType] {
        PasteboardIO.dropTypes
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }
    init(
        model: PanelModel,
        deliverPromise: @escaping PromiseDelivery = { promise, folder, reader in
            promise.receivePromisedFiles(
                atDestination: folder, options: [:], operationQueue: .main, reader: reader)
        }
    ) {
        self.model = model
        self.deliverPromise = deliverPromise
        super.init(frame: NSRect(origin: .zero, size: PanelMetrics.card))
        registerForDraggedTypes(Self.types)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { false }
    static func isSelfDrag(source: Any?, window: NSWindow?) -> Bool {
        guard let window, let view = source as? NSView else { return false }
        return view.window === window
    }
    private func isSelfDrag(_ sender: NSDraggingInfo) -> Bool {
        Self.isSelfDrag(source: sender.draggingSource, window: window)
    }
    static func eligible(_ pasteboard: NSPasteboard) -> Bool {
        let promises = filePromises(on: pasteboard)
        if !promises.isEmpty { return promises.contains(where: supportsPromise) }
        let files = ImageImportPayload.fileURLs(pasteboard)
        if !files.isEmpty { return files.contains(where: ImageImportPayload.plausibleImageFile) }
        return pasteboard.availableType(from: PasteboardIO.imageDataTypes) != nil
    }
    private static func filePromises(on board: NSPasteboard) -> [NSFilePromiseReceiver] {
        board.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
    }
    private static func supportsPromise(_ receiver: NSFilePromiseReceiver) -> Bool {
        receiver.fileTypes.contains { identifier in
            guard let type = UTType(identifier) ?? UTType(filenameExtension: identifier) else {
                return false
            }
            return ImageLoader.supports(type)
        }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !model.isWelcoming, !isSelfDrag(sender) else { return [] }
        let eligible = Self.eligible(sender.draggingPasteboard)
        onDragEligibility?(eligible)
        model.dropTarget = eligible
        return eligible ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { model.dropTarget = false }
    override func draggingEnded(_ sender: NSDraggingInfo) {
        model.dropTarget = false
        onDragEnd?()
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !model.isWelcoming && !isSelfDrag(sender) && Self.eligible(sender.draggingPasteboard)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !model.isWelcoming, !isSelfDrag(sender), Self.eligible(sender.draggingPasteboard) else { return false }
        model.dropTarget = false
        onDragEnd?()
        let board = sender.draggingPasteboard
        let promises = Self.filePromises(on: board).filter(Self.supportsPromise)
        // Capture's floating thumbnail can advertise an unfinished URL and image bytes
        // alongside the authoritative file promise. Receive it before reading those representations.
        if !promises.isEmpty {
            let token = model.reserveImport()
            let folder = DragTempFiles.directory.appendingPathComponent(
                "incoming-\(UUID())", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                model.importFailed(error.localizedDescription, token: token)
                return false
            }
            let receipt = PromisedImport(model: model, token: token, folder: folder)
            for promise in promises {
                deliverPromise(promise, folder) { url, error in
                    Task { @MainActor in await receipt.receive(url, error: error) }
                }
                // Legacy promises can write several files per type. fileNames is populated
                // only after receivePromisedFiles is called (NSFilePromiseReceiver contract).
                receipt.expect(promise.fileNames.count)
            }
            receipt.startTimeout()
            return true
        }
        // Capture the payload while the drag pasteboard is valid; decode away from the main actor.
        let payload = ImageImportPayload(board)
        guard !payload.isEmpty else { return false }
        let token = model.reserveImport()
        Task { [weak model] in
            do {
                let source = try await Task.detached(priority: .userInitiated) {
                    try payload.decode()
                }.value
                guard let model, model.state.token == token else { return }
                model.replace(with: source)
            } catch { model?.importFailed(error.localizedDescription, token: token) }
        }
        return true
    }
}
