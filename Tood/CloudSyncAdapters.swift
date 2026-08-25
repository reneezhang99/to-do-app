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

    func record(for id: UUID, zoneID: CKRecordZone.ID) -> CKRecord? {
        service.load().first { $0.id == id }?.toRecord(zoneID: zoneID)
    }

    func applyRemoteChanges(_ records: [CKRecord]) {
        let existingIDs = Set(service.load().map(\.id))
        for record in records {
            guard let archived = ArchivedSticky.from(record), !existingIDs.contains(archived.id) else { continue }
            service.append(archived)
        }
    }

    func applyRemoteDeletions(_ ids: [UUID]) {
        for id in ids { service.delete(id) }
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

    func record(for id: UUID, zoneID: CKRecordZone.ID) -> CKRecord? {
        service.load().first { $0.id == id }?.toRecord(zoneID: zoneID)
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
