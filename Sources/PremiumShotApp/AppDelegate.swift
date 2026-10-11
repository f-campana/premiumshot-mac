import AppKit
import PremiumShotMac

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = SessionStore()
    lazy var model = PanelModel(store: store)
    lazy var controller = PanelController(model: model)
    private var hotkey: GlobalHotkey?
    private var statusItem: NSStatusItem?
    private var loginItem: NSMenuItem?
    #if DEBUG
    var snapshotDefaultsName: String?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.removeObject(forKey: "panelPosition.v1")
        DragTempFiles.purge()
        let shortcut = GlobalHotkey { [weak self] in self?.controller.toggle() }
        let status = shortcut.register()
        hotkey = shortcut
        model.hotkeyUnavailable = status != 0
        if status != 0 { NSLog("PremiumShot: shortcut registration failed (%d).", status) }
        setUpStatusItem()
        #if DEBUG
        if startDeveloperMode(hotkeyStatus: status) { return }
        #endif
        if FirstLaunch.needsWelcome(in: model.defaults) { controller.showWelcome() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        #if DEBUG
        finishDeveloperMode()
        #endif
        hotkey?.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { controller.show() }
        return true
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarGlyph.image()
        item.button?.setAccessibilityLabel("PremiumShot")
        let menu = NSMenu()
        menu.delegate = self
        let show = menu.addItem(withTitle: "Show Panel", action: #selector(showPanel), keyEquivalent: " ")
        show.keyEquivalentModifierMask = [.command, .option, .shift]
        show.target = self
        menu.addItem(.separator())
        loginItem = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem?.target = self
        menu.addItem(.separator())
        let support = menu.addItem(withTitle: "Support PremiumShot ↗", action: #selector(openSupport), keyEquivalent: "")
        support.target = self
        support.isEnabled = AppInformation.supportURL != nil
        menu.autoenablesItems = false
        menu.addItem(withTitle: "About PremiumShot", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Welcome", action: #selector(showWelcome), keyEquivalent: "").target = self
        menu.addItem(.separator())
        #if DEBUG
        appendDeveloperMenu(to: menu)
        #endif
        menu.addItem(withTitle: "Quit PremiumShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.loginItems.refresh()
        loginItem?.state = model.loginItems.isRequested ? .on : .off
    }

    @objc private func showPanel() { controller.show() }
    @objc private func showWelcome() { controller.showWelcome() }
    @objc private func toggleLogin() {
        model.loginItems.setEnabled(!model.loginItems.isRequested)
        if model.loginItems.state == .needsApproval || model.loginItems.message != nil {
            model.loginItems.openSettings()
        }
    }
    @objc private func openSupport() {
        if let url = AppInformation.supportURL { NSWorkspace.shared.open(url) }
    }
    @objc private func showAbout() {
        controller.hide()
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: AppInformation.aboutOptions)
    }
}
