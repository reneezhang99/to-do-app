import CloudKit
import CoreGraphics
import Foundation
import Observation
import TootShared
import ToodAnalytics

/// The iPhone app's equivalent of the Mac's `StickyManager` — same local
/// JSON file convention and the same `SyncCollectionSource` contract, just
/// without any of the window/controller management that only makes sense
/// for floating desktop panels. A flat array is all a phone screen needs.
@MainActor
@Observable
final class MobileStickyStore {
    private(set) var stickies: [StickyData] = []

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("com.renee.Today", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("stickies.json")
        load()
        CloudSyncService.shared.register(self, for: .sticky)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        stickies = (try? decoder.decode([StickyData].self, from: data)) ?? []
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(stickies) else { return }
        try? data.write(to: fileURL, options: .atomic)
        // Keeps the Home Screen widget's App Group copy in lockstep with
        // every local edit, remote sync, and reorder — not just at launch.
        WidgetSnapshotStore.write(stickies)
    }

    /// Pulls whatever's changed on another device — called on launch and
    /// pull-to-refresh. No push notifications yet (see CloudSyncService's
    /// doc comment), so this is the phone-side half of how a Mac edit
    /// actually shows up here.
    func refreshFromCloud() async {
        await CloudSyncService.shared.pullRemoteChanges()
    }

    // MARK: - Mutations

    @discardableResult
    func newSticky() -> UUID {
        let sticky = StickyData(
            id: UUID(), title: "To Do", day: Date(),
            items: [TodoItem()], colorID: .nextNewStickyColor(), fontID: .defaultFont,
            frame: .zero, isVisible: true)
        stickies.insert(sticky, at: 0)
        commit(sticky.id)
        Analytics.track(.stickyCreated, ["open_sticky_count": stickies.count])
        return sticky.id
    }

    /// Local-only reordering of the home stack — mirrors the Mac's `order`
    /// array (also local, also not part of the synced `StickyData` fields):
    /// which sticky is "on top" isn't something that needs to agree across
    /// devices, just persist on this one.
    func moveSticky(from: Int, to: Int) {
        guard stickies.indices.contains(from) else { return }
        let item = stickies.remove(at: from)
        stickies.insert(item, at: min(max(to, 0), stickies.count))
        persist()
    }

    func setTitle(_ id: UUID, _ title: String) {
        mutate(id) { $0.title = title }
    }

    /// Free colors only — mirrors the Mac's `colorSwatchButton`, but mobile
    /// has no `ColorPackStore`/purchase flow yet, so paid Candy Pack colors
    /// aren't offered here even though `StickyColor` itself has the cases.
    func setColor(_ id: UUID, _ color: StickyColor) {
        mutate(id) { $0.colorID = color }
        Analytics.track(.stickyColorChanged, ["color": color.rawValue])
    }

    func setFont(_ id: UUID, _ font: StickyFont) {
        mutate(id) { $0.fontID = font }
        Analytics.track(.stickyFontChanged, ["font": font.rawValue])
    }

    func setItemText(_ id: UUID, _ itemID: UUID, _ text: String) {
        mutate(id) { data in
            guard let idx = data.items.firstIndex(where: { $0.id == itemID }) else { return }
            data.items[idx].text = text
        }
    }

    func toggleItem(_ id: UUID, _ itemID: UUID) {
        mutate(id) { data in
            guard let idx = data.items.firstIndex(where: { $0.id == itemID }) else { return }
            data.items[idx].isDone.toggle()
            data.items[idx].completedAt = data.items[idx].isDone ? Date() : nil
            Analytics.track(data.items[idx].isDone ? .itemCompleted : .itemReopened, ["via": "tap"])
        }
    }

    func addItem(_ id: UUID) {
        mutate(id) { $0.items.append(TodoItem()) }
        Analytics.track(.itemAdded)
    }

    /// The keyboard's indent button: tucks a row under the one above it, or
    /// pulls it back out. Same rules as Tab on the Mac: one level only, and
    /// the first row can't be tucked since nothing is above it.
    func setItemNested(_ id: UUID, _ itemID: UUID, _ isNested: Bool) {
        mutate(id) { data in
            guard let idx = data.items.firstIndex(where: { $0.id == itemID }),
                  data.items[idx].isNested != isNested,
                  !(isNested && idx == 0)
            else { return }
            data.items[idx].isNested = isNested
            if isNested { Analytics.track(.itemNested) }
        }
    }

    func deleteItem(_ id: UUID, _ itemID: UUID) {
        mutate(id) { $0.items.removeAll { $0.id == itemID } }
        Analytics.track(.itemDeleted)
    }

    /// Removes a whole sticky — the mobile equivalent of the Mac's
    /// `StickyManager.remove(_:)`. No archive option here (unlike the Mac):
    /// mobile has no archive-browsing UI yet, so offering it would just be
    /// a dead end.
    func deleteSticky(_ id: UUID) {
        let itemCount = stickies.first { $0.id == id }?.items.count ?? 0
        Analytics.track(.stickyDeleted, ["item_count": itemCount])
        stickies.removeAll { $0.id == id }
        persist()
        CloudSyncService.shared.delete(id: id, collection: .sticky)
        Task { await CloudSyncService.shared.pushLocalChanges() }
    }

    /// Every edit above funnels through here — updates `updatedAt` (so the
    /// Mac's last-write-wins comparison actually sees this as newer),
    /// persists locally, and queues the upload, mirroring exactly what
    /// `StickyModel.notifyChanged()` does on the Mac side.
    private func mutate(_ id: UUID, _ change: (inout StickyData) -> Void) {
        guard let idx = stickies.firstIndex(where: { $0.id == id }) else { return }
        change(&stickies[idx])
        stickies[idx].items.untuckFirstRow()
        stickies[idx].updatedAt = Date()
        commit(id)
    }

    private func commit(_ id: UUID) {
        persist()
        CloudSyncService.shared.save(id: id, collection: .sticky)
        Task { await CloudSyncService.shared.pushLocalChanges() }
    }
}

// MARK: - iCloud sync

extension MobileStickyStore: SyncCollectionSource {
    func record(for id: UUID, zoneID: CKRecordZone.ID) -> CKRecord? {
        stickies.first { $0.id == id }?.toRecord(zoneID: zoneID)
    }

    func applyRemoteChanges(_ records: [CKRecord]) {
        // Genuinely new stickies (not ones already here getting updated) go
        // to the top, oldest-of-the-batch first — so if several arrive in
        // one fetch, the most recently created ends up truly on top rather
        // than wherever CloudKit's fetch order happened to put it. Existing
        // stickies keep their current position when merely updated, so this
        // never fights a manual drag-reorder.
        var newlyArrived: [StickyData] = []
        for record in records {
            guard let data = StickyData.from(record) else { continue }
            if let idx = stickies.firstIndex(where: { $0.id == data.id }) {
                guard data.updatedAt > stickies[idx].updatedAt else { continue }
                stickies[idx] = data
            } else {
                newlyArrived.append(data)
            }
        }
        for data in newlyArrived.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            stickies.insert(data, at: 0)
        }
        persist()
    }

    func applyRemoteDeletions(_ ids: [UUID]) {
        stickies.removeAll { ids.contains($0.id) }
        persist()
    }
}
