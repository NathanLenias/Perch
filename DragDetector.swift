import AppKit
import UniformTypeIdentifiers

/// Which kinds of dragged content make the shelf appear. User-configurable
/// from the gear menu, persisted across launches.
enum ShelfTriggers {
    private static let filesKey = "showForFiles"
    private static let linksKey = "showForLinks"
    private static let textKey = "showForText"

    /// Files and images (Finder files, web images). On by default.
    static var files: Bool {
        get { UserDefaults.standard.object(forKey: filesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: filesKey) }
    }

    /// Web links. On by default.
    static var links: Bool {
        get { UserDefaults.standard.object(forKey: linksKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: linksKey) }
    }

    /// Text selections. Off by default: moving text inside a document is
    /// too common a gesture to hijack.
    static var text: Bool {
        get { UserDefaults.standard.object(forKey: textKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: textKey) }
    }

    /// Entries for building the "Show Shelf For" menu, shared by the gear
    /// popup and the menu bar menu.
    static func menuEntries() -> [(key: String, title: String, enabled: Bool)] {
        [
            ("files", String(localized: "trigger.files", defaultValue: "Files (images, PDFs…)"), files),
            ("links", String(localized: "trigger.links", defaultValue: "Links"), links),
            ("text", String(localized: "trigger.text", defaultValue: "Text"), text),
        ]
    }

    static func isEnabled(_ key: String) -> Bool {
        switch key {
        case "files": files
        case "links": links
        case "text": text
        default: false
        }
    }

    static func toggle(_ key: String) {
        switch key {
        case "files": files.toggle()
        case "links": links.toggle()
        case "text": text.toggle()
        default: break
        }
    }
}

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

            // Check if the drag carries something that should summon the shelf
            guard Self.pasteboardShouldSummonShelf(self.dragPasteboard) else { return }

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

    /// Should the shelf appear for this drag? Gated by the user's trigger
    /// preferences ("Show Shelf For" menu).
    static func pasteboardShouldSummonShelf(_ pasteboard: NSPasteboard) -> Bool {
        (ShelfTriggers.files && hasFileContent(pasteboard))
            || (ShelfTriggers.links && hasLinkContent(pasteboard))
            || (ShelfTriggers.text && hasTextContent(pasteboard))
    }

    /// Can the shelf take this drag at all? Deliberately NOT gated by the
    /// trigger preferences: those only control when the shelf appears; a
    /// visible shelf accepts everything it knows how to store.
    static func pasteboardHasSupportedContent(_ pasteboard: NSPasteboard) -> Bool {
        hasFileContent(pasteboard) || hasLinkContent(pasteboard) || hasTextContent(pasteboard)
    }

    private static func hasFileContent(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return true
        }
        if pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil) {
            return true
        }
        return pasteboard.canReadItem(withDataConformingToTypes: [UTType.image.identifier])
    }

    private static func hasLinkContent(_ pasteboard: NSPasteboard) -> Bool {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        return urls.contains { $0.scheme == "http" || $0.scheme == "https" }
    }

    private static func hasTextContent(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.string(forType: .string) != nil
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
