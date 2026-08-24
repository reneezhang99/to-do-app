import CloudKit
import Foundation
import Observation

/// Mirrors Tood's four local stores (stickies, archived stickies, archived
/// items, journal entries) to the user's private iCloud database via
/// `CKSyncEngine`, so the same data shows up on every device signed into
/// the same iCloud account. Local storage stays the source of truth — this
/// only ever pushes what's already been saved locally and folds down what
/// changed elsewhere; a CloudKit outage or a signed-out iCloud account
/// never blocks using the app.
///
/// One shared record zone ("TootZone") holds every record type; each
/// record's name is "<collection>_<uuid>" so an incoming change can be
/// routed to the right local store (see `SyncCollection`) without a
/// separate lookup.
///
/// No push notifications yet (would need the `aps-environment`
/// entitlement, which — per the Sparkle sandboxing bug earlier this
/// project — is exactly the kind of thing that's easy to get subtly wrong
/// in a way that only breaks for real users after ship). `pushLocalChanges`
/// and `pullRemoteChanges` are called explicitly instead: after every local
/// save, and periodically / on app activation. Worth adding push once this
/// baseline round-trip is proven solid.
@available(macOS 14.0, iOS 17.0, *)
@MainActor
@Observable
public final class CloudSyncService: NSObject {
    public static let containerIdentifier = "iCloud.com.renee.Today"
    public static let shared = CloudSyncService()

    private static let zoneName = "TootZone"
    private let zoneID: CKRecordZone.ID
    private let container: CKContainer
    private var syncEngine: CKSyncEngine!
    private var sources: [SyncCollection: SyncCollectionSource] = [:]
    private let metadata = RecordMetadataStore()

    /// True once CloudKit has confirmed the account is signed in and
    /// available — lets the app show a quiet "iCloud sync is off" hint
    /// instead of silently doing nothing. `@Observable` so a SwiftUI view
    /// can just read this and react.
    ///
    /// Starts optimistic (`true`) rather than `nil`/unknown, since most
    /// users are signed in and a flash of "not signed in" while the real
    /// check below is still in flight would be worse than briefly assuming
    /// the common case.
    public private(set) var accountAvailable = true

    private override init() {
        container = CKContainer(identifier: Self.containerIdentifier)
        zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        super.init()
        let config = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: Self.loadState(),
            delegate: self)
        syncEngine = CKSyncEngine(config)
        // Idempotent — CKSyncEngine coalesces this away once the zone
        // actually exists, so it's safe to queue unconditionally every
        // launch rather than tracking "have I done this before" ourselves.
        syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        // `accountAvailable` is otherwise only ever updated by a *change*
        // event (see `.accountChange` below) — which never fires if the
        // account was already signed out before this app launch, e.g. a
        // fresh device or a first-time install with iCloud off. Checking
        // the actual current status here is what catches that case.
        Task { await self.refreshAccountStatus() }
    }

    private func refreshAccountStatus() async {
        let status = (try? await container.accountStatus()) ?? .couldNotDetermine
        accountAvailable = (status == .available)
    }

    /// Registers the local store backing one collection. Call once per
    /// collection at launch, before any saves/deletes are queued.
    public func register(_ source: SyncCollectionSource, for collection: SyncCollection) {
        sources[collection] = source
    }

    /// Queues a local save (new or edited) for upload. Cheap to call on
    /// every edit — CKSyncEngine coalesces repeated saves of the same
    /// record into one upload.
    public func save(id: UUID, collection: SyncCollection) {
        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(for: id, collection: collection))])
    }

    public func delete(id: UUID, collection: SyncCollection) {
        syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID(for: id, collection: collection))])
    }

    /// Uploads everything currently queued. Called after the debounced
    /// local save already used by every store (`StickyManager.saveNow()`
    /// and friends) — piggybacks on that debounce rather than sending on
    /// every keystroke.
    public func pushLocalChanges() async {
        try? await syncEngine.sendChanges()
    }

    /// Pulls down anything changed on another device. Called on launch and
    /// periodically while the app is active (no push notifications yet).
    public func pullRemoteChanges() async {
        try? await syncEngine.fetchChanges()
    }

    private func recordID(for id: UUID, collection: SyncCollection) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(collection.rawValue)_\(id.uuidString)", zoneID: zoneID)
    }

    /// The collection a record name was saved under, and the sticky/entry
    /// ID within it — the inverse of `recordID(for:collection:)`.
    private func parse(_ recordID: CKRecord.ID) -> (SyncCollection, UUID)? {
        let name = recordID.recordName
        guard let underscore = name.firstIndex(of: "_") else { return nil }
        guard let collection = SyncCollection(rawValue: String(name[..<underscore])),
              let uuid = UUID(uuidString: String(name[name.index(after: underscore)...]))
        else { return nil }
        return (collection, uuid)
    }

    private static let stateDefaultsKey = "today.cloudSyncEngineState"

    private static func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: stateDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.stateDefaultsKey)
    }
}

// MARK: - CKSyncEngineDelegate

@available(macOS 14.0, iOS 17.0, *)
extension CloudSyncService: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization)

        case .accountChange(let change):
            switch change.changeType {
            case .signOut:
                accountAvailable = false
            case .signIn, .switchAccounts:
                accountAvailable = true
            @unknown default:
                break
            }

        case .fetchedRecordZoneChanges(let changes):
            var modifiedByCollection: [SyncCollection: [CKRecord]] = [:]
            for modification in changes.modifications {
                guard let (collection, _) = parse(modification.record.recordID) else { continue }
                metadata.store(modification.record)
                modifiedByCollection[collection, default: []].append(modification.record)
            }
            for (collection, records) in modifiedByCollection {
                sources[collection]?.applyRemoteChanges(records)
            }

            var deletedByCollection: [SyncCollection: [UUID]] = [:]
            for deletion in changes.deletions {
                guard let (collection, id) = parse(deletion.recordID) else { continue }
                metadata.remove(deletion.recordID)
                deletedByCollection[collection, default: []].append(id)
            }
            for (collection, ids) in deletedByCollection {
                sources[collection]?.applyRemoteDeletions(ids)
            }

        case .sentRecordZoneChanges(let event):
            for saved in event.savedRecords {
                metadata.store(saved)
            }
            for failure in event.failedRecordSaves {
                // A `.serverRecordChanged` conflict means another of the
                // user's own devices saved a newer version first (this is
                // a private, single-user database — there's no one else it
                // could be). Re-queuing after refreshing our cached system
                // fields to the server's copy is enough: the next batch
                // rebuilds the record from local data on top of the
                // server's change tag, so the retry actually succeeds
                // instead of conflicting again. Whichever side's edit is
                // newer wins for real once both are in — each store's own
                // `applyRemoteChanges` compares timestamps, it doesn't just
                // overwrite blindly.
                if failure.error.code == .serverRecordChanged, let serverRecord = failure.error.serverRecord {
                    metadata.store(serverRecord)
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
                }
            }

        default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] recordID in
            guard let self else { return nil }
            return await self.buildRecord(for: recordID)
        }
    }

    /// Everything `nextRecordZoneChangeBatch`'s recordProvider closure needs
    /// to do, hopped onto the main actor — the closure itself is
    /// `@Sendable`/non-isolated (CKSyncEngine can call it off the main
    /// actor), but every local store it touches lives on the main actor.
    private func buildRecord(for recordID: CKRecord.ID) async -> CKRecord? {
        guard let (collection, id) = parse(recordID),
              let record = sources[collection]?.record(for: id, zoneID: zoneID)
        else { return nil }
        // Carry over the last-known system fields (change tag) so this
        // reads as an update to the record CloudKit already has, not a
        // conflicting blind overwrite — see the .serverRecordChanged
        // handling above for why this matters.
        return metadata.applyCachedSystemFields(to: record)
    }
}
