import CloudKit
import Foundation

/// The four local stores that sync to iCloud — one CKRecord type per case.
/// The raw value doubles as the CKRecord type name and as the prefix of
/// every record's `recordName` (see `CloudSyncService.recordID(for:in:)`),
/// so it must stay stable — renaming a case would orphan every record
/// already synced under the old name.
@available(macOS 14.0, iOS 17.0, *)
public enum SyncCollection: String, CaseIterable, Sendable {
    case sticky = "Sticky"
    case archivedSticky = "ArchivedSticky"
    case archivedItem = "ArchivedItem"
    case journalEntry = "JournalEntry"
}

/// What a local store needs to implement so `CloudSyncService` can push its
/// pending edits up and fold remote edits back in, without CloudSyncService
/// itself knowing anything about the store's concrete type or on-disk
/// format. Each of Tood's four stores (stickies, archived stickies,
/// archived items, journal entries) adapts to this the same way; a future
/// iOS-side store can too.
///
/// Every method is called on the main actor — `CloudSyncService` itself is
/// main-actor isolated, matching where these stores already live (they're
/// `@Observable @MainActor` classes on the Mac app), so conformers don't
/// need their own synchronization.
@available(macOS 14.0, iOS 17.0, *)
@MainActor
public protocol SyncCollectionSource: AnyObject {
    /// Encodes the current local value for `id` as a CKRecord to upload, or
    /// `nil` if it no longer exists locally (already deleted locally after
    /// the change was queued, or never existed — CKSyncEngine asks for this
    /// lazily right before actually sending, not at the moment the change
    /// was queued).
    func record(for id: UUID, zoneID: CKRecordZone.ID) -> CKRecord?

    /// Records fetched from iCloud — either new from another device or
    /// changed since the last sync. Apply on top of local data; conflicts
    /// resolve by last-write-wins by comparing each type's own timestamp
    /// (`updatedAt`/`archivedAt`/etc.) since CloudKit's own modification
    /// date reflects upload time, not when the edit actually happened.
    func applyRemoteChanges(_ records: [CKRecord])

    /// Records deleted on another device — remove locally if still present.
    func applyRemoteDeletions(_ ids: [UUID])
}
