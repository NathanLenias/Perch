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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Positioning

    private let shelfWidth: CGFloat = 250
    private let shelfHeight: CGFloat = 360

    private var currentScreen: NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func shelfFrame(for screen: NSScreen, offScreen: Bool) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let y = visibleFrame.origin.y + (visibleFrame.height - shelfHeight) / 2
        let x = offScreen ? visibleFrame.origin.x - shelfWidth : visibleFrame.origin.x + 12

        return NSRect(x: x, y: y, width: shelfWidth, height: shelfHeight)
    }

    // MARK: - Show / Hide with animation

    var isShelfVisible = false

    func showShelf() {
        guard !isShelfVisible else { return }
        guard let window = window else { return }
        let screen = currentScreen
        isShelfVisible = true

        window.setFrame(shelfFrame(for: screen, offScreen: true), display: false)
        window.alphaValue = 0
        window.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(shelfFrame(for: screen, offScreen: false), display: true)
            window.animator().alphaValue = 1
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
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 1
        })
    }

    func toggleShelf() {
        if isShelfVisible { hideShelf() } else { showShelf() }
    }

}

// MARK: - ShelfPanel (non-activating panel)

private class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
