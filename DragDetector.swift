import AppKit

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
    }

    // MARK: - Event Monitors

    private func startMonitors() {
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            guard let self, !self.isActiveDrag else { return }

            let currentCount = self.dragPasteboard.changeCount
            guard currentCount != self.lastChangeCount else { return }
            self.lastChangeCount = currentCount

            // Check if the drag contains file URLs
            guard self.dragPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }

            self.isActiveDrag = true
            self.hideTimer?.invalidate()
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

    // MARK: - Mouse Up Handling

    private func handleMouseUp() {
        lastChangeCount = dragPasteboard.changeCount
        guard isActiveDrag else { return }
        isActiveDrag = false
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.delegate?.dragDetectorDidDetectDragEnd()
        }
    }
}
