import AppKit
import PremiumShotCore
import PremiumShotMac

/// Dev flags (documented in docs/M0-handoff.md):
///   --summon            show the panel at launch
///   --image <path>      use this file instead of the clipboard
///   --snapshot <png>    write the panel content to a PNG once the preview is ready, then quit
///   --self-test         print hotkey registration status as JSON and quit
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SessionStore()
    private lazy var model = PanelModel(store: store)
    private lazy var controller = PanelController(model: model)
    private var hotkey: GlobalHotkey?
    private var statusItem: NSStatusItem?

    private func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    private func has(_ flag: String) -> Bool { CommandLine.arguments.contains(flag) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)         // no Dock icon
        DragTempFiles.purge()
        if let path = value(after: "--image") { model.demoImageURL = URL(fileURLWithPath: path) }

        let hotkey = GlobalHotkey { [weak self] in self?.controller.toggle() }
        let status = hotkey.register()
        self.hotkey = hotkey

        if has("--self-test") {
            print("{\"hotkeyStatus\":\(status),\"hotkeyRegistered\":\(status == 0),\"conflict\":\(status == -9878)}")
            NSApp.terminate(nil); return
        }
        if status != 0 { NSLog("PremiumShot: hotkey registration failed with status %d%@", status, status == -9878 ? " (another app owns ⌘⌥⇧Space)" : "") }

        setUpStatusItem()
        if has("--summon") || has("--snapshot") { controller.show() }
        if let path = value(after: "--snapshot") { snapshotWhenReady(to: URL(fileURLWithPath: path)) }
    }

    private func snapshotWhenReady(to url: URL) {
        Task { @MainActor in
            for _ in 0..<100 where model.preview == nil && model.phase == .ready { try? await Task.sleep(for: .milliseconds(50)) }
            try? await Task.sleep(for: .milliseconds(300))
            let ok = controller.snapshot(to: url)
            print(ok ? "snapshot written to \(url.path)" : "snapshot failed")
            NSApp.terminate(nil)
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "PremiumShot")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Panel", action: #selector(togglePanel), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let spike = NSMenuItem(title: "Spike Tools", action: nil, keyEquivalent: "")
        let spikeMenu = NSMenu()
        spikeMenu.addItem(withTitle: "Drag-out test (S8)…", action: #selector(showDragTest), keyEquivalent: "").target = self
        spikeMenu.addItem(withTitle: "Swipe direction logger (S10)…", action: #selector(showGestureLogger), keyEquivalent: "").target = self
        spike.submenu = spikeMenu
        menu.addItem(spike)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PremiumShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() { controller.toggle() }
    @objc private func showDragTest() { SpikeHarness.shared.showDragTest() }
    @objc private func showGestureLogger() { SpikeHarness.shared.showGestureLogger() }
}
