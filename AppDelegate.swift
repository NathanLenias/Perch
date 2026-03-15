import AppKit

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
        menu.addItem(NSMenuItem(title: "Show Shelf", action: #selector(toggleShelf), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Clear Shelf", action: #selector(clearShelf), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Perch", action: #selector(quitApp), keyEquivalent: "q"))

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

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func updateMenuItemTitle() {
        if let menu = statusItem.menu, let item = menu.items.first {
            item.title = shelfWindowController.isShelfVisible ? "Hide Shelf" : "Show Shelf"
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
