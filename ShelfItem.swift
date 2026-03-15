import AppKit
import UniformTypeIdentifiers
import PDFKit

class ShelfItem {
    let url: URL
    let name: String
    let icon: NSImage
    let thumbnail: NSImage

    private static let thumbnailSize = NSSize(width: 160, height: 160)

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
        self.icon.size = NSSize(width: 32, height: 32)
        self.thumbnail = Self.generateThumbnail(for: url)
    }

    private static func generateThumbnail(for url: URL) -> NSImage {
        let type = UTType(filenameExtension: url.pathExtension)

        if type?.conforms(to: .image) == true, let image = NSImage(contentsOf: url) {
            return resize(image, to: thumbnailSize)
        }

        if type?.conforms(to: .pdf) == true,
           let page = PDFDocument(url: url)?.page(at: 0) {
            let pageImage = page.thumbnail(of: thumbnailSize, for: .mediaBox)
            return pageImage
        }

        // Fallback: system icon
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = thumbnailSize
        return icon
    }

    private static func resize(_ image: NSImage, to targetSize: NSSize) -> NSImage {
        let original = image.size
        let scale = min(targetSize.width / original.width, targetSize.height / original.height)
        let newSize = NSSize(width: original.width * scale, height: original.height * scale)

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: original),
                   operation: .copy,
                   fraction: 1.0)
        resized.unlockFocus()
        return resized
    }
}
