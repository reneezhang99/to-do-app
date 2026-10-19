import Foundation
import TootShared

/// Append-mostly JSON archive alongside the sticky store. "Mostly" — the
/// archive view also allows permanently deleting an entry to actually clean
/// up, unlike `ArchiveService`'s append-only item log.
struct StickyArchiveService {
    private let fileName = "archived_stickies.json"

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("com.renee.Today", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    func load() -> [ArchivedSticky] {
        SavedListFile.load(ArchivedSticky.self, from: fileURL)
    }

    private func save(_ all: [ArchivedSticky]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(all) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func append(_ sticky: ArchivedSticky) {
        append([sticky])
    }

    /// Adds several in one read and one write (iCloud hands them over in
    /// batches).
    func append(_ stickies: [ArchivedSticky]) {
        guard !stickies.isEmpty else { return }
        var all = load()
        all.append(contentsOf: stickies)
        save(all)
    }

    /// Removes an archived sticky for good — the archive view's own
    /// "Delete" action, for actually cleaning up old memories.
    func delete(_ id: UUID) {
        delete([id])
    }

    func delete(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let ids = Set(ids)
        var all = load()
        all.removeAll { ids.contains($0.id) }
        save(all)
    }

    var count: Int { load().count }
}
