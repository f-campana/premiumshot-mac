import AppKit
import PremiumShotCore
import PremiumShotMac

/// Dev flags (documented in docs/M0-handoff.md):
///   --summon            show the panel at launch
///   --image <path>      use this file instead of the clipboard
///   --snapshot <png>    write the panel content to a PNG once the preview is ready, then quit
///   --snapshot-action <copy|save>  capture feedback using a private clipboard or the snapshot folder
///   --self-test         print hotkey registration status as JSON and quit
///   --qa                show with isolated preferences and clipboard for native QA
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SessionStore()
    private lazy var model = PanelModel(store: store)
    private lazy var controller = PanelController(model: model)
    private var hotkey: GlobalHotkey?
    private var statusItem: NSStatusItem?
    private var snapshotDefaultsName: String?

    private func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    private func has(_ flag: String) -> Bool { CommandLine.arguments.contains(flag) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // no Dock icon
        UserDefaults.standard.removeObject(forKey: "panelPosition.v1")
        DragTempFiles.purge()
        if has("--snapshot") || has("--bench-workflow") || has("--qa") {
            let name = "com.fabien.premiumshot.snapshot.\(UUID())"
            snapshotDefaultsName = name
            model.defaults = UserDefaults(suiteName: name)!
            var recipe = Recipe.default
            if let id = value(after: "--look"), let look = LookID(rawValue: id) { recipe.look = look }
            if let id = value(after: "--shape"), let shape = Shape(rawValue: id) { recipe.shape = shape }
            RecipePersistence.save(recipe, to: model.defaults)
            if has("--snapshot") || has("--qa") {
                model.pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
                model.pasteboard.clearContents()
            }
            NSApp.appearance = NSAppearance(named: has("--dark") ? .darkAqua : .aqua)
        }
        if let path = value(after: "--image") { model.demoImageURL = URL(fileURLWithPath: path) }

        let defaults = UserDefaults.standard
        let key =
            defaults.object(forKey: "summonKeyCode") == nil
            ? GlobalHotkey.defaultKeyCode : UInt32(clamping: defaults.integer(forKey: "summonKeyCode"))
        let modifiers =
            defaults.object(forKey: "summonModifiers") == nil
            ? GlobalHotkey.defaultModifiers : UInt32(clamping: defaults.integer(forKey: "summonModifiers"))
        let hotkey = GlobalHotkey(keyCode: key, modifiers: modifiers) { [weak self] in
            self?.controller.toggle()
        }
        let status = hotkey.register()
        self.hotkey = hotkey

        if has("--self-test") {
            print(
                "{\"hotkeyStatus\":\(status),\"hotkeyRegistered\":\(status == 0),\"conflict\":\(status == -9878)}"
            )
            NSApp.terminate(nil)
            return
        }
        if has("--bench-workflow") {
            benchmarkWorkflow()
            return
        }
        if status != 0 {
            NSLog(
                "PremiumShot: hotkey registration failed with status %d%@", status,
                status == -9878 ? " (another app owns ⌘⌥⇧Space)" : "")
        }

        setUpStatusItem()
        if has("--summon") || has("--snapshot") || has("--qa") { controller.show() }
        if has("--expanded") { model.toggleDrawer() }
        if has("--inspect") { model.toggleInspect() }
        if let path = value(after: "--snapshot") { snapshotWhenReady(to: URL(fileURLWithPath: path)) }
    }

    private func benchmarkWorkflow() {
        Task { @MainActor in
            guard let url = model.demoImageURL, let data = try? Data(contentsOf: url) else {
                print("--bench-workflow needs --image")
                NSApp.terminate(nil)
                return
            }
            let pb = NSPasteboard(name: NSPasteboard.Name("com.fabien.premiumshot.bench.\(UUID())"))
            defer { pb.releaseGlobally() }
            pb.clearContents()
            pb.setData(data, forType: .png)
            model.pasteboard = pb
            model.demoImageURL = nil
            let clock = ContinuousClock()
            var maximumGap = 0.0
            let ticker = Task { @MainActor in
                var last = clock.now
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(5))
                    let now = clock.now
                    maximumGap = max(maximumGap, Timing.milliseconds(last.duration(to: now)))
                    last = now
                }
            }
            let began = clock.now
            if has("--bench-visible") { controller.show() } else { model.summon() }
            while model.frame == nil { try? await Task.sleep(for: .milliseconds(1)) }
            let firstFrame = Timing.milliseconds(began.duration(to: clock.now))
            while model.frame?.settled != true { try? await Task.sleep(for: .milliseconds(5)) }
            let settled = Timing.milliseconds(began.duration(to: clock.now))
            var start = clock.now
            await model.copy()
            let firstCopy = Timing.milliseconds(start.duration(to: clock.now))
            start = clock.now
            await model.copy()
            let memoisedCopy = Timing.milliseconds(start.duration(to: clock.now))
            ticker.cancel()
            let metrics = await model.renderMetrics()
            var interactiveTimes: [Double] = []
            model.beginSlider()
            for value in stride(from: 0, through: 100, by: 4) {
                start = clock.now
                model.edit { $0.space = value }
                let token = model.state.token
                while model.frame?.token != token {
                    try? await Task.sleep(for: .milliseconds(1))
                }
                interactiveTimes.append(Timing.milliseconds(start.duration(to: clock.now)))
            }
            model.endSlider()
            while model.frame?.settled != true { try? await Task.sleep(for: .milliseconds(1)) }
            let controlSettled = Timing.milliseconds(start.duration(to: clock.now))
            model.resetLook()
            start = clock.now
            await model.copy()
            let uncachedCopy = Timing.milliseconds(start.duration(to: clock.now))
            interactiveTimes.sort()
            let interactiveMedian = interactiveTimes[interactiveTimes.count / 2]
            let interactiveMax = interactiveTimes.last!
            print(
                "{\"firstFrameMs\":\(firstFrame),\"settledMs\":\(settled),\"firstCachedCopyMs\":\(firstCopy),\"memoisedCopyMs\":\(memoisedCopy),\"mainActorMaxGapMs\":\(maximumGap),\"renderCount\":\(metrics.renderCount),\"encodeCount\":\(metrics.encodeCount),\"interactiveMedianMs\":\(interactiveMedian),\"interactiveMaxMs\":\(interactiveMax),\"controlSettledMs\":\(controlSettled),\"uncachedCopyMs\":\(uncachedCopy)}"
            )
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let name = snapshotDefaultsName {
            model.defaults.removePersistentDomain(forName: name)
            if has("--snapshot") || has("--qa") { model.pasteboard.releaseGlobally() }
        }
    }

    private func snapshotWhenReady(to url: URL) {
        Task { @MainActor in
            for _ in 0..<100 where model.preview == nil && model.phase == .ready {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if value(after: "--snapshot-action") == "copy" { await model.copy() }
            if value(after: "--snapshot-action") == "save" {
                await model.save(to: url.deletingLastPathComponent())
            }
            try? await Task.sleep(for: .milliseconds(300))
            let ok = controller.snapshot(to: url)
            if ok { try? controller.snapshotLayout(to: url.deletingPathExtension().appendingPathExtension("json")) }
            print(ok ? "snapshot written to \(url.path)" : "snapshot failed")
            NSApp.terminate(nil)
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "PremiumShot")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Panel", action: #selector(togglePanel), keyEquivalent: "").target = self
        menu.addItem(.separator())
        if has("--spike-tools") {
            let spike = NSMenuItem(title: "Spike Tools", action: nil, keyEquivalent: "")
            let spikeMenu = NSMenu()
            spikeMenu.addItem(
                withTitle: "Drag-out test (S8)…", action: #selector(showDragTest), keyEquivalent: ""
            ).target = self
            spikeMenu.addItem(
                withTitle: "Swipe direction logger (S10)…", action: #selector(showGestureLogger),
                keyEquivalent: ""
            ).target = self
            spike.submenu = spikeMenu
            menu.addItem(spike)
            menu.addItem(.separator())
        }
        menu.addItem(
            withTitle: "Quit PremiumShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() { controller.toggle() }
    @objc private func showDragTest() { SpikeHarness.shared.showDragTest() }
    @objc private func showGestureLogger() { SpikeHarness.shared.showGestureLogger() }
}
