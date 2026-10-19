import Foundation
import TootShared

/// Append-only JSON archive alongside the sticky store.
struct ArchiveService {
    private let fileName = "archive.json"

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("com.renee.Today", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    func load() -> [ArchivedItem] {
        SavedListFile.load(ArchivedItem.self, from: fileURL)
    }

    func append(_ items: [ArchivedItem]) {
        guard !items.isEmpty else { return }
        var all = load()
        all.append(contentsOf: items)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(all) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    var count: Int { load().count }
}
