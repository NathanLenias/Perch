import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private lazy var shelfWindowController = ShelfWindowController()
    private let dragDetector = DragDetector()

    func applicationDidFinishLaunching(_ notification: Notification) {
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

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
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

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func updateMenuItemTitle() {
        if let menu = statusItem.menu, let item = menu.items.first {
            item.title = shelfWindowController.isShelfVisible
                ? String(localized: "menu.hidePerch", defaultValue: "Hide Perch")
                : String(localized: "menu.showPerch", defaultValue: "Show Perch")
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
