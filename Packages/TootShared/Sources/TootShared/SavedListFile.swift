import Foundation

/// Reads a saved JSON list (stickies, archive, journal) from disk.
///
/// Every store here loads, changes, then writes the whole file back. So if
/// a file ever can't be read, "load" used to come back empty and the next
/// save quietly replaced everything with that empty list. Now an unreadable
/// file gets copied aside first (`<name>.unreadable-<time>.json`), so the
/// data is still on disk to recover, whatever happens next.
public enum SavedListFile {
    public static func load<Element: Decodable>(_ type: Element.Type, from url: URL) -> [Element] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([Element].self, from: data)
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = url.deletingPathExtension()
                .appendingPathExtension("unreadable-\(stamp)")
                .appendingPathExtension("json")
            try? FileManager.default.copyItem(at: url, to: backup)
            print("SavedListFile: couldn't read \(url.lastPathComponent), copied it to \(backup.lastPathComponent): \(error)")
            return []
        }
    }
}
