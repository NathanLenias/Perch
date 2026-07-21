import AppKit
import UniformTypeIdentifiers

class DropTargetView: NSVisualEffectView {

    /// Real files landed on the shelf.
    var onDrop: (([URL]) -> Void)?
    /// A web drop (promise or download) started; returns a pending-row id.
    var onPendingBegin: (() -> UUID)?
    /// A web drop finished; nil URL means it failed.
    var onPendingResolved: ((UUID, URL?) -> Void)?

    private let promiseQueue = OperationQueue()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        var types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .tiff, .png, .string]
        types += NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes(types)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isDroppable(sender.draggingPasteboard) else {
            return []
        }
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.perchAccent.withAlphaComponent(0.6).cgColor
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDroppable(sender.draggingPasteboard) ? .copy : []
    }

    /// The drop target takes more than what makes the shelf appear: plain
    /// text doesn't summon the shelf, but is welcome once it's visible.
    private func isDroppable(_ pasteboard: NSPasteboard) -> Bool {
        DragDetector.pasteboardHasShelvableContent(pasteboard)
            || pasteboard.string(forType: .string) != nil
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderWidth = 0
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderWidth = 0
        let pasteboard = sender.draggingPasteboard

        // 1. Real files: reference them directly, the historical path
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            onDrop?(urls)
            return true
        }

        // 2. File promises: how browsers hand over dragged images
        if let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)
            as? [NSFilePromiseReceiver], !receivers.isEmpty {
            for receiver in receivers { receive(receiver) }
            return true
        }

        // 3. Remote URL alongside image data: a dragged web image, download it
        if let remote = remoteURL(from: pasteboard) {
            if hasImageData(pasteboard) {
                guard let pendingID = onPendingBegin?() else { return false }
                DropStore.download(from: remote) { [weak self] localURL in
                    self?.onPendingResolved?(pendingID, localURL)
                }
                return true
            }
            // 4. Remote URL without image data: a link, keep it as .webloc
            let title = pasteboard.string(forType: NSPasteboard.PasteboardType("public.url-name"))
            if let url = DropStore.writeLink(remote, title: title) {
                onDrop?([url])
                return true
            }
            return false
        }

        // 5. Raw image data only: write it out as a file
        if let (data, type) = imageData(from: pasteboard), let url = DropStore.write(data: data, type: type) {
            onDrop?([url])
            return true
        }

        // 6. Plain text: keep it as a .txt file
        if let text = pasteboard.string(forType: .string), !text.isEmpty,
           let url = DropStore.writeText(text) {
            onDrop?([url])
            return true
        }

        return false
    }

    // MARK: - Web content handling

    private func receive(_ receiver: NSFilePromiseReceiver) {
        guard let pendingID = onPendingBegin?() else { return }
        let destination = DropStore.makeDropFolder()
        receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: promiseQueue) { [weak self] url, error in
            DispatchQueue.main.async {
                self?.onPendingResolved?(pendingID, error == nil ? url : nil)
            }
        }
    }

    private func remoteURL(from pasteboard: NSPasteboard) -> URL? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return nil
        }
        return urls.first { $0.scheme == "http" || $0.scheme == "https" }
    }

    private func hasImageData(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadItem(withDataConformingToTypes: [UTType.image.identifier])
    }

    private func imageData(from pasteboard: NSPasteboard) -> (Data, UTType)? {
        if let png = pasteboard.data(forType: .png) {
            return (png, .png)
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            return (png, .png)
        }
        return nil
    }
}
