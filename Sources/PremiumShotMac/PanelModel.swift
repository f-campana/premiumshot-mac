import AppKit
import Observation
import PremiumShotCore

public struct PreviewFrame: Sendable {
    public let token: WorkToken
    public let recipe: Recipe
    public let render: RenderResult
    public let settled: Bool
}

@MainActor @Observable
public final class PanelModel {
    public enum Phase: Equatable {
        case empty(String?)
        case alreadyPolished, ready
    }
    public enum Status: Equatable {
        case copied(String)
        case saved(String)
        case notice(String)
        case error(String)
    }
    public enum Focus: Equatable { case panel, preview, look, control }
    public private(set) var state = PanelState()
    public private(set) var frame: PreviewFrame?
    public private(set) var status: Status?
    public private(set) var progressVisible = false
    public private(set) var copySequence: UInt64 = 0
    public private(set) var removalThumbnail: CGImage?
    public var focus: Focus = .panel
    public var keyboardFocus = false
    public var dropTarget = false
    public var canExpand = true
    public var backingScale: CGFloat = 2
    public var demoImageURL: URL?
    public var pasteboard: NSPasteboard = .general
    public var defaults: UserDefaults = .standard
    public var pasteboardWriter: (Data, UUID, (width: Int, height: Int), NSPasteboard) -> Bool = {
        PasteboardIO.writePNG($0, marker: $1, expectedSize: $2, to: $3)
    }
    public var renderFull: RenderCache.Render = { try Renderer.render(source: $0, recipe: $1, profile: $2) }
    public var encodePNG: RenderCache.Encode = { try PNG.encode($0.image) }
    public var onPresentationChange: (() -> Void)?
    var onPresentationSnap: (() -> Void)?
    public var onFocusPreview: (() -> Void)?
    var onKeyLoopChange: (() -> Void)?
    public private(set) var gradientPresentation: UInt64 = 0
    private(set) var gradientPresentationActive = false
    @ObservationIgnored private var gradientStart: CGImage?
    public var needsSaveFolder = false
    private let store: SessionStore
    private var session: SourceSession?
    private var pendingPolished: SourceImage?
    private var cache = RenderCache()
    private let queue = RenderQueue()
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    public private(set) var presentationImage: CGImage?
    @ObservationIgnored private var motionTask: Task<Void, Never>?
    @ObservationIgnored private var motion: CompositionMotion?
    private var pendingFrame: PreviewFrame?
    private var animateGeometry = false
    private var sliderEditing = false
    private var statusToken = 0
    private var copying: WorkToken?
    private var saving: WorkToken?
    public init(store: SessionStore) { self.store = store }
    public static let canvasBox = CGSize(width: 544, height: 300)
    public var recipe: Recipe { state.recipe }
    public var preview: CGImage? { presentationImage ?? frame?.render.image }
    public var layout: Layout? { frame?.render.layout }
    public var previewGeneration: UInt64 { state.revision }
    public var currentSession: SourceSession? { session }
    public var isCopying: Bool { copying != nil }
    public var isReady: Bool { session != nil }
    public var isImporting: Bool { state.importing }
    public var isInspecting: Bool { state.inspect }
    public var isExpanded: Bool { state.drawer }
    public var phase: Phase {
        switch state.mode {
        case .ready: .ready
        case .alreadyPolished: .alreadyPolished
        case .empty(let reason): .empty(reason)
        case .hidden: .empty(nil)
        }
    }
    public var profile: ExportProfile {
        ExportProfile(rawValue: defaults.string(forKey: "exportProfile") ?? "srgb") ?? .srgb
    }

    public func summon() {
        removalThumbnail = nil
        invalidate()
        setStatus(nil)
        pendingPolished = nil
        frame = nil
        state.drawer = false
        state.inspect = false
        let recipe = RecipePersistence.load(from: defaults)
        let resolved: SummonSource
        if let url = demoImageURL, let source = try? ImageLoader.load(url: url) {
            resolved = .image(source)
        } else {
            resolved = SummonSource.resolve(pasteboard: pasteboard, store: store)
        }
        switch resolved {
        case .session(let session): begin(session)
        case .image(let source): begin(store.add(source: source, recipe: recipe))
        case .alreadyPolished(let image):
            session = nil
            pendingPolished = image
            state.transition(to: .alreadyPolished, recipe: recipe)
        case .empty(let reason):
            session = nil
            state.transition(to: .empty(reason), recipe: recipe)
        }
    }
    public func dismiss() {
        removalThumbnail = nil
        persist()
        invalidate()
        frame = nil
        pendingPolished = nil
        session = nil
        state.transition(to: .hidden)
        setStatus(nil)
        focus = .panel
        dropTarget = false
    }
    public func removeScreenshot() {
        guard let session, !state.inspect else { return }
        // Only the small rendered thumbnail survives the exit animation, never the decoded source.
        removalThumbnail = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : preview
        invalidate()
        store.remove(id: session.id)
        self.session = nil
        pendingPolished = nil
        frame = nil
        state.transition(to: .empty(nil))
        setStatus(nil)
        focus = .panel
        needsSaveFolder = false
        onPresentationChange?()
        let token = state.token
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, self.state.token == token else { return }
            self.removalThumbnail = nil
        }
    }
    public func replace(with source: SourceImage) {
        removalThumbnail = nil
        invalidate()
        frame = nil
        pendingPolished = nil
        setStatus(nil)
        begin(store.add(source: source, recipe: recipe))
    }
    private func begin(_ session: SourceSession) {
        self.session = session
        frame = nil
        state.transition(to: .ready(session.id), recipe: session.recipe)
        focus = .preview
        renderPreview()
        onFocusPreview?()
    }
    public func useAlreadyPolishedAnyway() {
        guard let source = pendingPolished else { return }
        replace(with: source)
    }
    public func paste() {
        switch PasteboardIO.read(from: pasteboard) {
        case .image(let source, _): replace(with: source)
        case .none(let reason):
            if let reason {
                importError(reason)
            } else if isReady {
                setStatus(.notice("The clipboard has no image."))
            } else {
                state.transition(to: .empty(reason))
                pendingPolished = nil
            }
        }
    }
    /// Reserve before asking a drop provider for bytes so two out-of-order drops cannot race.
    @discardableResult public func reserveImport() -> WorkToken {
        finishMotion()
        invalidate()
        setStatus(nil)
        state.importing = true
        let token = state.token
        progressTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, self.state.token == token, self.isImporting else { return }
            self.progressVisible = true
        }
        return token
    }
    public func importFailed(_ message: String, token: WorkToken) {
        guard token == state.token else { return }
        state.importing = false
        progressVisible = false
        importError(message)
        if session != nil && frame == nil { renderPreview() }
    }
    public func load(url: URL, reservedToken: WorkToken? = nil) {
        let token = reservedToken ?? reserveImport()
        guard token == state.token else { return }
        Task {
            do {
                let source = try await Task.detached(priority: .userInitiated) {
                    try ImageLoader.load(url: url)
                }.value
                guard token == state.token else { return }
                replace(with: source)
            } catch {
                guard token == state.token else { return }
                importFailed(error.localizedDescription, token: token)
            }
        }
    }
    public func load(data: Data, reservedToken: WorkToken? = nil) {
        let token = reservedToken ?? reserveImport()
        guard token == state.token else { return }
        Task {
            do {
                let source = try await Task.detached(priority: .userInitiated) {
                    try ImageLoader.load(data: data)
                }.value
                guard token == state.token else { return }
                replace(with: source)
            } catch {
                guard token == state.token else { return }
                importFailed(error.localizedDescription, token: token)
            }
        }
    }
    public func openLatest() {
        let token = reserveImport()
        let folder = LatestScreenshot.folder
        Task {
            do {
                let found = try await Task.detached(priority: .userInitiated) {
                    try LatestScreenshot.find(in: folder)
                }.value
                guard token == state.token else { return }
                if let found {
                    load(url: found, reservedToken: token)
                } else {
                    importFailed("No screenshot found in \(folder.lastPathComponent).", token: token)
                }
            } catch {
                guard token == state.token else { return }
                importFailed(error.localizedDescription, token: token)
            }
        }
    }
    private func importError(_ message: String) {
        if isReady {
            setStatus(.error(message))
        } else {
            pendingPolished = nil
            state.transition(to: .empty(message))
        }
    }
    public func constrainExpansion(to available: Bool) {
        canExpand = available
        if !available { state.drawer = false }
    }
    public func toggleDrawer() {
        guard isReady, canExpand, !state.inspect else { return }
        state.drawer.toggle()
        onPresentationChange?()
    }
    public func toggleInspect() {
        guard isReady else { return }
        finishMotion()
        state.inspect.toggle()
        onPresentationChange?()
    }
    public func closeInspect() {
        state.inspect = false
        focus = .preview
        onPresentationChange?()
        onFocusPreview?()
    }

    public func setRecipe(_ next: Recipe, record: Bool = true) {
        guard isReady, next != recipe else { return }
        if record { session?.history.record(before: recipe, after: next) }
        animateGeometry = !sliderEditing
        state.changeRecipe(next)
        session?.recipe = next
        invalidate(clearMotion: false)
        setStatus(nil)
        renderPreview()
        schedulePersistence()
    }
    public func edit(_ change: (inout Recipe) -> Void) {
        var next = recipe
        change(&next)
        setRecipe(next)
    }
    public func cycleLook(_ delta: Int) {
        let looks = LookID.allCases
        let index = looks.firstIndex(of: recipe.look)!
        edit { $0.look = looks[(index + delta + looks.count) % looks.count] }
    }
    public func beginSlider() {
        guard !sliderEditing else { return }
        sliderEditing = true
        finishMotion()
        session?.history.beginDrag(recipe)
    }
    public func endSlider() {
        guard sliderEditing else { return }
        sliderEditing = false
        session?.history.endDrag(recipe)
        schedulePersistence()
    }
    public func undo() {
        endSlider()
        if let previous = session?.history.undo(recipe) { setRecipe(previous, record: false) }
    }
    public func redo() {
        endSlider()
        if let next = session?.history.redo(recipe) { setRecipe(next, record: false) }
    }
    public func resetLook() {
        endSlider()
        setRecipe(.default)
    }
    public func randomizeGradient() {
        var random = SystemRandomNumberGenerator()
        randomizeGradient(using: &random)
    }
    func randomizeGradient<R: RandomNumberGenerator>(using rng: inout R) {
        guard isReady else { return }
        endSlider()
        let source = preview
        let pair = GradientHues(from: recipe.gradientFrom, to: recipe.gradientTo).randomized(using: &rng)
        edit {
            $0.look = .custom
            $0.gradientFrom = pair.from
            $0.gradientTo = pair.to
        }
        gradientPresentationActive = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        gradientStart = gradientPresentationActive ? source : nil
        gradientPresentation &+= 1
    }
    private func schedulePersistence() {
        persistenceTask?.cancel()
        persistenceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            persist()
        }
    }
    private func persist() { RecipePersistence.save(recipe, to: defaults) }

    private func invalidate(clearMotion: Bool = true) {
        gradientStart = nil
        motionTask?.cancel()
        pendingFrame = nil
        if clearMotion {
            motion = nil
            presentationImage = nil
            animateGeometry = false
        }
        state.invalidate()
        previewTask?.cancel()
        settleTask?.cancel()
        progressTask?.cancel()
        progressVisible = false
        copying = nil
        saving = nil
        let old = cache
        cache = RenderCache(render: renderFull, encode: encodePNG)
        Task { await old.invalidate() }
    }
    private var previewHeight: Int {
        guard let source = session?.source else { return 600 }
        let layout = LayoutEngine.resolve(
            sourceWidth: source.width, sourceHeight: source.height, recipe: recipe)
        let aspect = Double(layout.width) / Double(layout.height)
        return max(
            1, Int((min(Self.canvasBox.height, Self.canvasBox.width / aspect) * backingScale).rounded(.down)))
    }
    public func renderPreview() {
        guard let session else { return }
        let token = state.token
        let source = session.source
        let recipe = self.recipe
        let profile = self.profile
        let height = previewHeight
        let cache = self.cache
        progressTask?.cancel()
        if frame == nil {
            progressTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, state.token == token, frame == nil else { return }
                progressVisible = true
            }
        }
        previewTask?.cancel()
        previewTask = Task { [weak self, queue] in
            do {
                guard
                    let result = try await queue.interactive(
                        source: source, recipe: recipe, profile: profile, height: height)
                else { return }
                guard let self, !Task.isCancelled, self.state.token == token else { return }
                self.accept(PreviewFrame(token: token, recipe: recipe, render: result, settled: false))
                self.progressVisible = false
            } catch { self?.renderError(error, token: token) }
        }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            do {
                // Keep full renders out of a moving slider's fast path without spending half
                // the settled-preview budget waiting. The approximate 150 ms spec is tuned here.
                try await Task.sleep(for: .milliseconds(125))
                let result = try await cache.preview(
                    source: source, recipe: recipe, profile: profile, height: height)
                guard let self, !Task.isCancelled, self.state.token == token else { return }
                self.accept(PreviewFrame(token: token, recipe: recipe, render: result, settled: true))
                self.progressVisible = false
            } catch { self?.renderError(error, token: token) }
        }
    }
    private func accept(_ next: PreviewFrame) {
        guard next.token == state.token else { return }
        if let source = gradientStart, !state.inspect {
            gradientStart = nil
            animateGeometry = false
            frame = next
            pendingFrame = next
            presentationImage = source
            let token = next.token
            motionTask = Task { [weak self] in
                let clock = ContinuousClock()
                let began = clock.now
                while let self, self.state.token == token, !Task.isCancelled,
                    let target = self.pendingFrame?.render.image
                {
                    let t = min(1, Timing.milliseconds(began.duration(to: clock.now)) / 250)
                    if t == 1 {
                        self.finishMotion()
                        return
                    }
                    self.presentationImage = GradientCrossfade.image(from: source, to: target, fraction: t)
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
            return
        }
        if pendingFrame?.token == next.token {
            pendingFrame = next
            return
        }
        let target = PresentationGeometry(next.render.layout)
        let previous = motion?.geometry ?? frame.map { PresentationGeometry($0.render.layout) }
        guard animateGeometry, !state.inspect, let previous, let session,
            frame?.token.sessionID == next.token.sessionID,
            previous != target,
            frame?.render.layout.window != next.render.layout.window
                || frame?.render.layout.width != next.render.layout.width
                || frame?.render.layout.height != next.render.layout.height,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else {
            finishMotion()
            frame = next
            return
        }
        if motion != nil {
            motion?.retarget(target)
        } else {
            motion = CompositionMotion(from: previous, to: target)
        }
        // Numbers belong to the committed target; the UI-only raster carries
        // the in-between geometry and is never used by an output action.
        presentationImage = preview
        frame = next
        pendingFrame = next
        motionTask?.cancel()
        let token = next.token
        let source = session.source
        let profile = self.profile
        motionTask = Task { [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            let began = last
            while let self, !Task.isCancelled, self.state.token == token {
                let now = clock.now
                self.motion?.advance(seconds: Timing.milliseconds(last.duration(to: now)) / 1000)
                last = now
                guard let current = self.motion else { return }
                if current.finished || Timing.milliseconds(began.duration(to: now)) > 600 {
                    self.finishMotion()
                    return
                }
                let geometry = current.geometry
                // Fit the current interpolated aspect, not the target aspect. Otherwise a
                // thin strip changing to Square could allocate an enormous transient bitmap.
                let aspect = geometry.aspectRatio(reference: next.render.layout)
                let height = max(
                    1,
                    Int(
                        (min(Self.canvasBox.height, Self.canvasBox.width / aspect) * self.backingScale)
                            .rounded(.down)))
                guard
                    let result = try? await Task.detached(
                        priority: .userInitiated,
                        operation: {
                            try Renderer.renderPresentation(
                                source: source, recipe: next.recipe, profile: profile,
                                geometry: geometry, height: height)
                        }
                    ).value, !Task.isCancelled, self.state.token == token
                else { return }
                self.presentationImage = result.image
                let remaining = 16 - Timing.milliseconds(now.duration(to: clock.now))
                if remaining > 0 {
                    try? await Task.sleep(for: .milliseconds(remaining))
                } else {
                    await Task.yield()
                }
            }
        }
    }
    public func finishMotion() {
        gradientPresentationActive = false
        gradientStart = nil
        motionTask?.cancel()
        if let pendingFrame, pendingFrame.token == state.token { frame = pendingFrame }
        pendingFrame = nil
        presentationImage = nil
        motion = nil
        animateGeometry = false
    }

    private func renderError(_ error: Error, token: WorkToken) {
        guard token == state.token, !(error is CancellationError) else { return }
        progressVisible = false
        setStatus(.error("Too large to render. Try a smaller shape."))
    }
    public func fullImage() async -> CGImage? {
        guard let session else { return nil }
        let token = state.token
        let cache = self.cache
        let recipe = self.recipe
        let profile = self.profile
        guard
            let result = try? await cache.resolved(source: session.source, recipe: recipe, profile: profile),
            token == state.token
        else { return nil }
        return result.image
    }
    public func copy() async {
        guard isReady, let session, copying == nil else { return }
        finishMotion()
        onPresentationSnap?()
        let token = state.token
        let cache = self.cache
        let recipe = self.recipe
        let profile = self.profile
        copying = token
        defer { if copying == token { copying = nil } }
        do {
            let output = try await cache.encoded(source: session.source, recipe: recipe, profile: profile)
            guard token == state.token else { return }
            let l = output.render.layout
            guard pasteboardWriter(output.png, session.id, (l.width, l.height), pasteboard) else {
                setStatus(.error("Couldn't copy to the clipboard."))
                return
            }
            if frame?.token != token {
                frame = PreviewFrame(token: token, recipe: recipe, render: output.render, settled: true)
            }
            copySequence &+= 1
            setStatus(.copied("Copied \(l.width) × \(l.height) px"))
        } catch {
            guard token == state.token, !(error is CancellationError) else { return }
            setStatus(.error(error.localizedDescription))
        }
    }
    public func renderMetrics() async -> (renderCount: Int, encodeCount: Int) {
        (await cache.renderCount, await cache.encodeCount)
    }

    public var saveFolder: URL {
        if let path = defaults.string(forKey: "saveFolder") { return URL(fileURLWithPath: path) }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }
    public func save(to folder: URL? = nil) async {
        guard isReady, let session, saving == nil else { return }
        finishMotion()
        onPresentationSnap?()
        let token = state.token
        let cache = self.cache
        let recipe = self.recipe
        let profile = self.profile
        let folder = folder ?? saveFolder
        saving = token
        defer { if saving == token { saving = nil } }
        do {
            let output = try await cache.encoded(source: session.source, recipe: recipe, profile: profile)
            guard token == state.token else { return }
            let url = try FileOutput.save(output.png, directory: folder)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw CocoaError(.fileWriteUnknown)
            }
            needsSaveFolder = false
            let l = output.render.layout
            setStatus(.saved("Saved \(l.width) × \(l.height) px"))
        } catch {
            guard token == state.token, !(error is CancellationError) else { return }
            needsSaveFolder = true
            setStatus(.error("Couldn't save to \(folder.lastPathComponent)."))
        }
    }
    public func chooseSaveFolder() {
        let token = state.token
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose folder"
        NSApp.activate()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self, self.state.token == token else { return }
            self.defaults.set(url.path, forKey: "saveFolder")
            Task { await self.save(to: url) }
        }
    }
    public func prepareDrag() async -> URL? {
        guard isReady, let session else { return nil }
        finishMotion()
        onPresentationSnap?()
        let token = state.token
        let cache = self.cache
        let recipe = self.recipe
        let profile = self.profile
        do {
            let output = try await cache.encoded(source: session.source, recipe: recipe, profile: profile)
            guard token == state.token else { return nil }
            return try DragTempFiles.write(output.png, name: "Screenshot \(UUID().uuidString) polished.png")
        } catch {
            guard token == state.token, !(error is CancellationError) else { return nil }
            setStatus(.error("Couldn't prepare the image for dragging."))
            return nil
        }
    }
    public func notice(_ text: String) { setStatus(.notice(text)) }
    private func setStatus(_ new: Status?) {
        status = new
        statusToken += 1
        guard new != nil else { return }
        let id = statusToken
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.7))
            if self?.statusToken == id { self?.status = nil }
        }
    }
}
