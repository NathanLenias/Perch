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
        var types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .tiff, .png]
        types += NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes(types)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard DragDetector.pasteboardHasShelvableContent(sender.draggingPasteboard) else {
            return []
        }
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.perchAccent.withAlphaComponent(0.6).cgColor
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        DragDetector.pasteboardHasShelvableContent(sender.draggingPasteboard) ? .copy : []
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

        // 3. No promise but a remote URL alongside image data: download it
        if let remote = remoteURL(from: pasteboard) {
            guard let pendingID = onPendingBegin?() else { return false }
            DropStore.download(from: remote) { [weak self] localURL in
                self?.onPendingResolved?(pendingID, localURL)
            }
            return true
        }

        // 4. Raw image data only: write it out as a file
        if let (data, type) = imageData(from: pasteboard), let url = DropStore.write(data: data, type: type) {
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
