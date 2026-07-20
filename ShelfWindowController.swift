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
        // .fullScreenAuxiliary is required so the shelf can appear over full-screen apps
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false

        let viewController = ShelfViewController()
        window.contentViewController = viewController
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Positioning

    private let shelfWidth: CGFloat = 380
    private let shelfHeight: CGFloat = 540

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

    /// Incremented on every show/hide so a stale hide animation's completion
    /// handler can't order the window out after a newer show started.
    private var animationGeneration = 0

    func showShelf() {
        guard !isShelfVisible else { return }
        guard let window = window else { return }
        let screen = currentScreen
        isShelfVisible = true
        animationGeneration += 1

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
        animationGeneration += 1
        let generation = animationGeneration

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(self.shelfFrame(for: screen, offScreen: true), display: true)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // A newer show/hide started during this animation — don't touch the window
            guard let self, generation == self.animationGeneration else { return }
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
    // Accepting key status lets the shelf receive Cmd+V/Cmd+C after a click;
    // the .nonactivatingPanel style keeps the app from stealing activation.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let vc = contentViewController as? ShelfViewController else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "v":
            vc.pasteFromClipboard()
            return true
        case "c":
            vc.copySelection()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}
