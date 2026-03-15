import AppKit

class ShelfWindowController: NSWindowController {

    init() {
        let window = ShelfPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false

        let viewController = ShelfViewController()
        window.contentViewController = viewController
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 12
        window.contentView?.layer?.masksToBounds = true

        // Window starts hidden; position is calculated at show time
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Positioning

    private let shelfWidth: CGFloat = 200

    /// Returns the screen where the mouse cursor currently is.
    private var currentScreen: NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func shelfFrame(for screen: NSScreen, offScreen: Bool) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let shelfHeight = max(visibleFrame.height * 0.6, 100)
        let y = visibleFrame.origin.y + (visibleFrame.height - shelfHeight) / 2
        let x = offScreen ? visibleFrame.origin.x - shelfWidth : visibleFrame.origin.x

        return NSRect(x: x, y: y, width: shelfWidth, height: shelfHeight)
    }

    // MARK: - Show / Hide with animation

    var isShelfVisible = false

    func showShelf() {
        guard !isShelfVisible else { return }
        guard let window = window else { return }
        let screen = currentScreen
        isShelfVisible = true

        // Start off-screen to the left
        window.setFrame(shelfFrame(for: screen, offScreen: true), display: false)
        window.orderFront(nil)

        // Slide in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(shelfFrame(for: screen, offScreen: false), display: true)
        }
    }

    func hideShelf() {
        guard isShelfVisible else { return }
        guard let window = window else { return }
        let screen = currentScreen
        isShelfVisible = false

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(self.shelfFrame(for: screen, offScreen: true), display: true)
        }, completionHandler: {
            window.orderOut(nil)
        })
    }

    func toggleShelf() {
        if isShelfVisible { hideShelf() } else { showShelf() }
    }
}

// MARK: - ShelfPanel (non-activating panel)

private class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
