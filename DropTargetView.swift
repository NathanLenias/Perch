import AppKit

class DropTargetView: NSVisualEffectView {

    var onDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: fileReadingOptions) else {
            return []
        }
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: fileReadingOptions) else {
            return []
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderWidth = 0
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderWidth = 0
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: fileReadingOptions
        ) as? [URL] else {
            return false
        }
        onDrop?(urls)
        return true
    }

    private var fileReadingOptions: [NSPasteboard.ReadingOptionKey: Any] {
        [.urlReadingFileURLsOnly: true]
    }
}
