import CloudKit
import TootShared

/// Adapts `StickyArchiveService` — a plain struct that just reads/writes a
/// JSON file, no in-memory cache, no class to conform directly — to
/// `SyncCollectionSource`. Archived stickies are immutable snapshots once
/// created (nothing in the app edits one after archiving), so there's no
/// real last-write-wins case here: applying a remote change is just
/// "add it if we don't already have it."
@MainActor
final class ArchivedStickySyncAdapter: SyncCollectionSource {
    private let service: StickyArchiveService
    init(service: StickyArchiveService) { self.service = service }

    /// Archived stickies never change, so a copy in memory stays correct.
    /// A big upload asks for hundreds of records in a row, and re-reading
    /// the whole archive file for each one made first sync crawl. A miss
    /// (something archived since) just re-reads the file.
    private var cache: [UUID: ArchivedSticky] = [:]

    func record(for id: UUID, zoneID: CKRecordZone.ID) -> CKRecord? {
        if cache[id] == nil {
            cache = Dictionary(service.load().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return cache[id]?.toRecord(zoneID: zoneID)
    }

    func applyRemoteChanges(_ records: [CKRecord]) {
        var seen = Set(service.load().map(\.id))
        let new = records.compactMap(ArchivedSticky.from).filter { seen.insert($0.id).inserted }
        service.append(new)
    }

    func applyRemoteDeletions(_ ids: [UUID]) {
        service.delete(ids)
        for id in ids { cache[id] = nil }
    }
}

/// Same idea as `ArchivedStickySyncAdapter`, for `ArchiveService`'s
/// completed-task history. No per-item delete exists anywhere in the app
/// today, so `applyRemoteDeletions` has nothing to do — there's nothing
/// that could have produced that deletion in the first place.
@MainActor
final class ArchivedItemSyncAdapter: SyncCollectionSource {
    private let service: ArchiveService
    init(service: ArchiveService) { self.service = service }

    /// Same in-memory copy as `ArchivedStickySyncAdapter`'s, for the same
    /// reason: archived items never change once written.
    private var cache: [UUID: ArchivedItem] = [:]

    func record(for id: UUID, zoneID: CKRecordZone.ID) -> CKRecord? {
        if cache[id] == nil {
            cache = Dictionary(service.load().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return cache[id]?.toRecord(zoneID: zoneID)
    }

    func applyRemoteChanges(_ records: [CKRecord]) {
        let existingIDs = Set(service.load().map(\.id))
        let new = records.compactMap(ArchivedItem.from).filter { !existingIDs.contains($0.id) }
        service.append(new)
    }

    func applyRemoteDeletions(_ ids: [UUID]) {
        // Nothing deletes individual archived items today — see doc comment above.
    }
}
