#if DEBUG
import AppKit
import PremiumShotCore
import PremiumShotMac

/// Debug-only diagnostics. These strings and the spike harness are absent from the release binary.
@MainActor extension AppDelegate {
    func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    func has(_ flag: String) -> Bool { CommandLine.arguments.contains(flag) }

    func startDeveloperMode(hotkeyStatus: Int32) -> Bool {
        let isolated = has("--snapshot") || has("--bench-workflow") || has("--qa") || has("--welcome")
        if isolated {
            let name = "com.fabien.premiumshot.snapshot.\(UUID())"
            snapshotDefaultsName = name
            model.defaults = UserDefaults(suiteName: name)!
            var recipe = Recipe.default
            if let id = value(after: "--look"), let look = LookID(rawValue: id) { recipe.look = look }
            if let id = value(after: "--shape"), let shape = Shape(rawValue: id) { recipe.shape = shape }
            RecipePersistence.save(recipe, to: model.defaults)
            model.pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
            model.pasteboard.clearContents()
            NSApp.appearance = NSAppearance(named: has("--dark") ? .darkAqua : .aqua)
        }
        if let path = value(after: "--image") { model.demoImageURL = URL(fileURLWithPath: path) }
        if has("--folder-denied") {
            model.findLatestScreenshot = { _ in throw CocoaError(.fileReadNoPermission) }
        }
        if has("--self-test") {
            print("{\"hotkeyStatus\":\(hotkeyStatus),\"hotkeyRegistered\":\(hotkeyStatus == 0)}")
            NSApp.terminate(nil)
            return true
        }
        if has("--bench-workflow") { benchmarkWorkflow(); return true }
        if has("--welcome") { controller.showWelcome() }
        else if has("--summon") || has("--snapshot") || has("--qa") { controller.show() }
        if has("--expanded") { model.toggleDrawer() }
        if has("--inspect") { model.toggleInspect() }
        if has("--folder-denied") { model.openLatest() }
        if let path = value(after: "--snapshot") { snapshotWhenReady(to: URL(fileURLWithPath: path)) }
        return isolated || has("--summon") || has("--spike-tools") || has("--image")
    }

    func finishDeveloperMode() {
        if let name = snapshotDefaultsName {
            model.defaults.removePersistentDomain(forName: name)
            model.pasteboard.releaseGlobally()
        }
    }

    func appendDeveloperMenu(to menu: NSMenu) {
        guard has("--spike-tools") else { return }
        let tools = NSMenuItem(title: "Spike Tools", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(withTitle: "Drag-out test…", action: #selector(showDragTest), keyEquivalent: "").target = self
        submenu.addItem(withTitle: "Swipe direction logger…", action: #selector(showGestureLogger), keyEquivalent: "").target = self
        tools.submenu = submenu
        menu.addItem(tools)
        menu.addItem(.separator())
    }
    @objc func showDragTest() { SpikeHarness.shared.showDragTest() }
    @objc func showGestureLogger() { SpikeHarness.shared.showGestureLogger() }
    func benchmarkWorkflow() {
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

    func snapshotWhenReady(to url: URL) {
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

}
#endif
