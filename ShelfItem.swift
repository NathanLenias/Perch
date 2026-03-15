import AppKit

class ShelfItem {
    let url: URL
    let name: String
    let icon: NSImage

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
        self.icon.size = NSSize(width: 32, height: 32)
    }
}
