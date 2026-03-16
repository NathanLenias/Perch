import AppKit
import UniformTypeIdentifiers
import PDFKit

class ShelfItem {
    let urls: [URL]
    let name: String
    let icon: NSImage
    let thumbnail: NSImage

    var isGroup: Bool { urls.count > 1 }
    var url: URL { urls[0] }
    var fileCount: Int { urls.count }

    private static let thumbnailSize = NSSize(width: 160, height: 160)

    init(url: URL) {
        self.urls = [url]
        self.name = url.lastPathComponent
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
        self.icon.size = NSSize(width: 32, height: 32)
        self.thumbnail = Self.generateThumbnail(for: url)
    }

    init(urls: [URL]) {
        precondition(urls.count >= 2)
        self.urls = urls
        self.name = String(localized: "group.fileCount \(urls.count)")

        // Composite stacked icon from up to 3 first files
        let stackIcons = urls.prefix(3).map { url -> NSImage in
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            return icon
        }
        self.icon = Self.compositeStackedIcon(from: stackIcons, size: NSSize(width: 32, height: 32))

        // Larger composite for thumbnail
        let thumbIcons = urls.prefix(3).map { url -> NSImage in
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = Self.thumbnailSize
            return icon
        }
        self.thumbnail = Self.compositeStackedIcon(from: thumbIcons, size: Self.thumbnailSize)
    }

    // MARK: - Stacked icon compositing

    private static func compositeStackedIcon(from icons: [NSImage], size: NSSize) -> NSImage {
        guard !icons.isEmpty else { return NSImage() }
        if icons.count == 1 { return icons[0] }

        let offset: CGFloat = size.width * 0.08  // ~8% offset per layer
        let totalOffset = offset * CGFloat(icons.count - 1)
        let canvasSize = NSSize(width: size.width + totalOffset, height: size.height + totalOffset)
        let iconSize = NSSize(width: size.width * 0.85, height: size.height * 0.85)

        let composite = NSImage(size: canvasSize)
        composite.lockFocus()

        for (i, icon) in icons.reversed().enumerated() {
            let reverseIndex = icons.count - 1 - i
            let x = CGFloat(reverseIndex) * offset
            let y = CGFloat(i) * offset
            let rect = NSRect(origin: NSPoint(x: x, y: y), size: iconSize)

            // Subtle shadow for depth
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 2
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
            shadow.set()

            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        composite.unlockFocus()
        return composite
    }

    // MARK: - Single-file thumbnail

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
