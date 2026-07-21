import AppKit
import ServiceManagement

extension NSColor {
    /// Perch's amber accent, adaptive light/dark (defined in Assets.xcassets).
    static var perchAccent: NSColor { NSColor(named: "AccentAmber") ?? .controlAccentColor }
}

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private lazy var shelfWindowController = ShelfWindowController()
    private let dragDetector = DragDetector()

    func applicationDidFinishLaunching(_ notification: Notification) {
        DropStore.cleanOrphans()
        setupMenuBar()
        setupShelfCallbacks()
        dragDetector.delegate = self
        dragDetector.start()
    }

    private func setupShelfCallbacks() {
        if let vc = shelfWindowController.window?.contentViewController as? ShelfViewController {
            vc.onBecameEmpty = { [weak self] in
                guard let self else { return }
                self.shelfWindowController.hideShelf()
                self.updateMenuItemTitle()
            }
            vc.onHideRequested = { [weak self] in
                guard let self else { return }
                self.shelfWindowController.hideShelf()
                self.updateMenuItemTitle()
            }
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(named: "MenuBarIcon")
        }

        let menu = NSMenu()

        menu.addItem(NSMenuItem(
            title: String(localized: "menu.showPerch", defaultValue: "Show Perch"),
            action: #selector(toggleShelf), keyEquivalent: "s"
        ))
        menu.addItem(NSMenuItem(
            title: String(localized: "menu.clearPerch", defaultValue: "Clear Perch"),
            action: #selector(clearShelf), keyEquivalent: ""
        ))

        menu.addItem(NSMenuItem.separator())

        let launchItem = NSMenuItem(
            title: String(localized: "menu.launchAtLogin", defaultValue: "Launch Perch at Login"),
            action: #selector(toggleLaunchAtLogin), keyEquivalent: ""
        )
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

        let showForItem = NSMenuItem(
            title: String(localized: "menu.showFor", defaultValue: "Show Shelf For"),
            action: nil, keyEquivalent: ""
        )
        let showForMenu = NSMenu()
        showForMenu.delegate = self
        for entry in ShelfTriggers.menuEntries() {
            let item = NSMenuItem(title: entry.title, action: #selector(triggerToggled(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.key
            item.state = entry.enabled ? .on : .off
            showForMenu.addItem(item)
        }
        menu.addItem(showForItem)
        menu.setSubmenu(showForMenu, for: showForItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: String(localized: "menu.about", defaultValue: "About Perch"),
            action: #selector(showAbout), keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: String(localized: "menu.quit", defaultValue: "Quit Perch"),
            action: #selector(quitApp), keyEquivalent: "q"
        ))

        menu.items.forEach { $0.target = self }
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func toggleShelf() {
        shelfWindowController.toggleShelf()
        updateMenuItemTitle()
    }

    @objc private func clearShelf() {
        if let vc = shelfWindowController.window?.contentViewController as? ShelfViewController {
            vc.clearAll()
        }
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            // Registration failed silently — user can retry
        }
    }

    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func triggerToggled(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        ShelfTriggers.toggle(key)
    }

    private func updateMenuItemTitle() {
        if let menu = statusItem.menu, let item = menu.items.first {
            item.title = shelfWindowController.isShelfVisible
                ? String(localized: "menu.hidePerch", defaultValue: "Hide Perch")
                : String(localized: "menu.showPerch", defaultValue: "Show Perch")
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        updateMenuItemTitle()
        for item in menu.items {
            if item.action == #selector(toggleLaunchAtLogin) {
                item.state = SMAppService.mainApp.status == .enabled ? .on : .off
            }
            // Trigger toggles may also be changed from the gear menu;
            // refresh their checkmarks whenever the menu opens
            if let key = item.representedObject as? String {
                item.state = ShelfTriggers.isEnabled(key) ? .on : .off
            }
        }
    }
}

// MARK: - DragDetectorDelegate

extension AppDelegate: DragDetectorDelegate {

    func dragDetectorDidDetectDragStart() {
        shelfWindowController.showShelf()
        updateMenuItemTitle()
    }

    func dragDetectorDidDetectDragEnd() {
        // Keep the shelf visible if it has items
        if let vc = shelfWindowController.window?.contentViewController as? ShelfViewController, vc.hasItems {
            return
        }
        shelfWindowController.hideShelf()
        updateMenuItemTitle()
    }
}
