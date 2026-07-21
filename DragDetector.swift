import AppKit
import UniformTypeIdentifiers

protocol DragDetectorDelegate: AnyObject {
    func dragDetectorDidDetectDragStart()
    func dragDetectorDidDetectDragEnd()
}

class DragDetector {

    weak var delegate: DragDetectorDelegate?

    private var globalDragMonitor: Any?
    private var globalUpMonitor: Any?
    private var localUpMonitor: Any?
    private var hideTimer: Timer?
    private var dragEndPollTimer: Timer?

    private let dragPasteboard = NSPasteboard(name: .drag)
    private var lastChangeCount: Int = 0
    private var isActiveDrag = false

    static let resyncNotification = Notification.Name("DragDetectorResync")

    func start() {
        lastChangeCount = dragPasteboard.changeCount
        startMonitors()

        NotificationCenter.default.addObserver(forName: Self.resyncNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.lastChangeCount = self.dragPasteboard.changeCount
        }
    }

    func stop() {
        if let m = globalDragMonitor { NSEvent.removeMonitor(m); globalDragMonitor = nil }
        if let m = globalUpMonitor { NSEvent.removeMonitor(m); globalUpMonitor = nil }
        if let m = localUpMonitor { NSEvent.removeMonitor(m); localUpMonitor = nil }
        hideTimer?.invalidate()
        dragEndPollTimer?.invalidate()
    }

    // MARK: - Event Monitors

    private func startMonitors() {
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            guard let self else { return }

            // The change count is the source of truth: a new value means a new
            // drag session, even if the previous session's mouseUp was never
            // delivered (the system can swallow it), so don't gate on isActiveDrag.
            let currentCount = self.dragPasteboard.changeCount
            guard currentCount != self.lastChangeCount else { return }
            self.lastChangeCount = currentCount

            // Check if the drag carries something we can shelve
            guard Self.pasteboardHasShelvableContent(self.dragPasteboard) else { return }

            self.isActiveDrag = true
            self.hideTimer?.invalidate()
            self.startDragEndPolling()
            self.delegate?.dragDetectorDidDetectDragStart()
        }

        globalUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleMouseUp()
        }

        localUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleMouseUp()
            return event
        }
    }

    // MARK: - Shelvable content

    /// True when a drag carries content the shelf can take: real files,
    /// file promises (how browsers drag images), or raw image data.
    /// Deliberately NOT text or bare links, to keep the shelf from popping
    /// up on tab drags and text selections.
    static func pasteboardHasShelvableContent(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return true
        }
        if pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil) {
            return true
        }
        if pasteboard.canReadItem(withDataConformingToTypes: [UTType.image.identifier]) {
            return true
        }
        return false
    }

    // MARK: - Mouse Up Handling

    private func handleMouseUp() {
        lastChangeCount = dragPasteboard.changeCount
        guard isActiveDrag else { return }
        isActiveDrag = false
        dragEndPollTimer?.invalidate()
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.delegate?.dragDetectorDidDetectDragEnd()
        }
    }

    // MARK: - Drag End Polling (safety net)

    /// Event monitors can miss the mouseUp that ends a drag session, which used
    /// to leave the detector stuck. While a drag is active, poll the physical
    /// button state so a missed mouseUp still ends the session.
    private func startDragEndPolling() {
        dragEndPollTimer?.invalidate()
        dragEndPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isActiveDrag else {
                self.dragEndPollTimer?.invalidate()
                return
            }
            // Bit 0 = left button. If it's up, the drag is over.
            if NSEvent.pressedMouseButtons & 0x1 == 0 {
                self.handleMouseUp()
            }
        }
    }
}
