import AppKit
import UniformTypeIdentifiers
import PDFKit

class ShelfItem {
    let urls: [URL]
    let name: String
    let icon: NSImage
    let thumbnail: NSImage

    /// Short description shown under the name: "PDF · 248 KB" for files,
    /// "Group · PDF, PNG" for stacks.
    let subtitle: String

    var isGroup: Bool { urls.count > 1 }
    var url: URL { urls[0] }
    var fileCount: Int { urls.count }

    /// Page count for PDFs, nil for everything else. Loaded on first access.
    lazy var pageCount: Int? = {
        guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true else { return nil }
        return PDFDocument(url: url)?.pageCount
    }()

    private static let thumbnailSize = NSSize(width: 160, height: 160)

    init(url: URL) {
        self.urls = [url]
        self.name = url.lastPathComponent
        self.subtitle = Self.fileSubtitle(for: url)
        self.icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        self.icon.size = NSSize(width: 32, height: 32)
        self.thumbnail = Self.generateThumbnail(for: url)
    }

    init(urls: [URL]) {
        precondition(urls.count >= 2)
        self.urls = urls
        self.name = String(localized: "group.fileCount \(urls.count)")
        self.subtitle = Self.groupSubtitle(for: urls)

        // Composite stacked icon from up to 3 first files
        let stackIcons = urls.prefix(3).map { url -> NSImage in
            let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
            icon.size = NSSize(width: 32, height: 32)
            return icon
        }
        self.icon = Self.compositeStackedIcon(from: stackIcons, size: NSSize(width: 32, height: 32))

        // Larger composite for thumbnail
        let thumbIcons = urls.prefix(3).map { url -> NSImage in
            let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
            icon.size = Self.thumbnailSize
            return icon
        }
        self.thumbnail = Self.compositeStackedIcon(from: thumbIcons, size: Self.thumbnailSize)
    }

    // MARK: - Subtitles

    private static func fileSubtitle(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        let isDirectory = values?.isDirectory ?? false

        var parts: [String] = []
        if let label = typeLabel(for: url, isDirectory: isDirectory) {
            parts.append(label)
        }
        if !isDirectory, let size = values?.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    private static func groupSubtitle(for urls: [URL]) -> String {
        let label = String(localized: "group.label", defaultValue: "Group")
        var seen = Set<String>()
        let types = urls.compactMap { url -> String? in
            let ext = url.pathExtension.uppercased()
            guard !ext.isEmpty, !seen.contains(ext) else { return nil }
            seen.insert(ext)
            return ext
        }
        guard !types.isEmpty else { return label }
        return "\(label) · \(types.prefix(3).joined(separator: ", "))"
    }

    private static func typeLabel(for url: URL, isDirectory: Bool) -> String? {
        let ext = url.pathExtension
        if !ext.isEmpty { return ext.uppercased() }
        if isDirectory { return String(localized: "item.folder", defaultValue: "Folder") }
        return UTType(filenameExtension: ext)?.localizedDescription
    }

    // MARK: - Stacked icon compositing

    private static func compositeStackedIcon(from icons: [NSImage], size: NSSize) -> NSImage {
        guard !icons.isEmpty else { return NSImage() }
        if icons.count == 1 { return icons[0] }

        let offset: CGFloat = size.width * 0.08  // ~8% offset per layer
        let totalOffset = offset * CGFloat(icons.count - 1)
        let canvasSize = NSSize(width: size.width + totalOffset, height: size.height + totalOffset)
        let iconSize = NSSize(width: size.width * 0.85, height: size.height * 0.85)

        return NSImage(size: canvasSize, flipped: false) { _ in
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
            return true
        }
    }

    // MARK: - Single-file thumbnail

    private static let maxThumbnailFileSize: Int = 50_000_000 // 50 MB

    private static func generateThumbnail(for url: URL) -> NSImage {
        let type = UTType(filenameExtension: url.pathExtension)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0

        if type?.conforms(to: .image) == true, fileSize < maxThumbnailFileSize,
           let image = NSImage(contentsOf: url) {
            return resize(image, to: thumbnailSize)
        }

        if type?.conforms(to: .pdf) == true, fileSize < maxThumbnailFileSize,
           let page = PDFDocument(url: url)?.page(at: 0) {
            let pageImage = page.thumbnail(of: thumbnailSize, for: .mediaBox)
            return pageImage
        }

        // Fallback: system icon
        let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        icon.size = thumbnailSize
        return icon
    }

    private static func resize(_ image: NSImage, to targetSize: NSSize) -> NSImage {
        let original = image.size
        let scale = min(targetSize.width / original.width, targetSize.height / original.height)
        let newSize = NSSize(width: original.width * scale, height: original.height * scale)

        return NSImage(size: newSize, flipped: false) { rect in
            image.draw(in: rect, from: NSRect(origin: .zero, size: original),
                       operation: .copy, fraction: 1.0)
            return true
        }
    }
}
