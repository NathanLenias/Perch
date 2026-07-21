import AppKit
import UniformTypeIdentifiers
import PDFKit
import QuickLookThumbnailing

class ShelfItem {
    private(set) var urls: [URL]
    private(set) var name: String
    let icon: NSImage

    /// File bookmarks captured at drop time (Finder-alias mechanism); they
    /// keep resolving after the file is moved or renamed on the same volume.
    /// Regenerated after each resolution — stale bookmark data may not
    /// survive a second move.
    private var bookmarks: [Data?]

    /// Starts as the file icon (instant), then swaps to the real Quick Look
    /// thumbnail once the system generates it off the main thread.
    private(set) var thumbnail: NSImage

    /// Called on the main thread when the async thumbnail arrives, so the
    /// currently displayed view can refresh its image.
    var onThumbnailUpdated: ((NSImage) -> Void)?

    /// Locked items stay in the shelf after a drag-out, for files that get
    /// reused over and over. Off by default.
    var isLocked = false

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
        self.bookmarks = [try? url.bookmarkData()]
        self.subtitle = Self.fileSubtitle(for: url)
        self.icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        self.icon.size = NSSize(width: 48, height: 48)

        // Instant placeholder; the real thumbnail arrives asynchronously
        let placeholder = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        placeholder.size = Self.thumbnailSize
        self.thumbnail = placeholder
        generateThumbnailAsync(for: url)
    }

    /// Asks Quick Look for a thumbnail off the main thread. For big photos
    /// (RAW…) this uses the embedded preview instead of decoding the full
    /// image, so dropping a file never blocks the UI.
    private func generateThumbnailAsync(for url: URL) {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: Self.thumbnailSize,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let self, let cgImage = representation?.cgImage else { return }
            let image = NSImage(cgImage: cgImage, size: .zero)
            DispatchQueue.main.async {
                self.thumbnail = image
                self.onThumbnailUpdated?(image)
            }
        }
    }

    init(urls: [URL]) {
        precondition(urls.count >= 2)
        self.urls = urls
        self.name = String(localized: "group.fileCount \(urls.count)")
        self.bookmarks = urls.map { try? $0.bookmarkData() }
        self.subtitle = Self.groupSubtitle(for: urls)

        // Composite stacked icon from up to 3 first files
        let stackIcons = urls.prefix(3).map { url -> NSImage in
            let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
            icon.size = NSSize(width: 48, height: 48)
            return icon
        }
        self.icon = Self.compositeStackedIcon(from: stackIcons, size: NSSize(width: 48, height: 48))

        // Larger composite for thumbnail
        let thumbIcons = urls.prefix(3).map { url -> NSImage in
            let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
            icon.size = Self.thumbnailSize
            return icon
        }
        self.thumbnail = Self.compositeStackedIcon(from: thumbIcons, size: Self.thumbnailSize)
    }

    // MARK: - Moved file tracking

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Re-resolves any file that is no longer at its recorded path through its
    /// bookmark, so a moved or renamed file keeps being reachable from the shelf.
    /// Called right before a drag starts and after a drag-out, so the shelf
    /// always hands out the file's current location.
    func refreshMovedFiles() {
        for (index, url) in urls.enumerated() {
            guard !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
                  let data = bookmarks[index] else { continue }
            var isStale = false
            guard let resolved = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale),
                  FileManager.default.fileExists(atPath: resolved.path(percentEncoded: false)) else { continue }
            urls[index] = resolved
            bookmarks[index] = try? resolved.bookmarkData()
        }
        if !isGroup { name = url.lastPathComponent }
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
        if ext.lowercased() == "webloc" { return String(localized: "item.link", defaultValue: "Link") }
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

}
