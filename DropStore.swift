import AppKit
import UniformTypeIdentifiers

/// Storage for files Perch materializes itself, like web images dragged from
/// a browser. Unlike regular shelf items, which reference files elsewhere on
/// disk, files in here are owned by Perch: they are deleted when their item
/// leaves the shelf, and leftovers are swept at launch.
enum DropStore {

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Perch/Drops", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A fresh subfolder for one incoming drop, so promised files with the
    /// same name never collide across drops.
    static func makeDropFolder() -> URL {
        let dir = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func isOwned(_ url: URL) -> Bool {
        url.path(percentEncoded: false).hasPrefix(folder.path(percentEncoded: false))
    }

    /// Deletes a file if Perch owns it (no-op for the user's own files).
    static func deleteIfOwned(_ url: URL) {
        guard isOwned(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Downloads a remote image into the store. Completion on the main thread,
    /// nil on failure.
    static func download(from remoteURL: URL, completion: @escaping (URL?) -> Void) {
        let task = URLSession.shared.downloadTask(with: remoteURL) { tempURL, response, _ in
            var result: URL?
            if let tempURL {
                let destination = makeDropFolder()
                    .appendingPathComponent(suggestedName(for: remoteURL, response: response))
                if (try? FileManager.default.moveItem(at: tempURL, to: destination)) != nil {
                    result = destination
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
    }

    /// Writes raw image data (a drag carrying neither promise nor usable URL).
    static func write(data: Data, type: UTType) -> URL? {
        let ext = type.preferredFilenameExtension ?? "png"
        let destination = makeDropFolder().appendingPathComponent("Image.\(ext)")
        do {
            try data.write(to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// Writes a dropped link as a .webloc file (macOS's native link format:
    /// double-clickable, opens the browser).
    static func writeLink(_ remote: URL, title: String?) -> URL? {
        let baseName = sanitizeFilename(title ?? remote.host() ?? "Link")
        let destination = makeDropFolder().appendingPathComponent("\(baseName).webloc")
        let plist = ["URL": remote.absoluteString]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            return nil
        }
        do {
            try data.write(to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// Writes dropped text as a UTF-8 .txt file named after its first words.
    static func writeText(_ text: String) -> URL? {
        let firstLine = text.split(separator: "\n", maxSplits: 1).first ?? ""
        let baseName = sanitizeFilename(String(firstLine.prefix(30)))
        let destination = makeDropFolder().appendingPathComponent("\(baseName).txt")
        do {
            try text.write(to: destination, atomically: true, encoding: .utf8)
            return destination
        } catch {
            return nil
        }
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? String(localized: "drop.untitled", defaultValue: "Untitled") : cleaned
    }

    /// Items don't persist across launches, so anything left in the store at
    /// startup belongs to no one. Sweep it all.
    static func cleanOrphans() {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func suggestedName(for remoteURL: URL, response: URLResponse?) -> String {
        if let suggested = response?.suggestedFilename, !suggested.isEmpty {
            return suggested
        }
        let last = remoteURL.lastPathComponent
        if !last.isEmpty, last != "/" {
            return last
        }
        return "Image.png"
    }
}
