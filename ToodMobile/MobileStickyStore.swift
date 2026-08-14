import CloudKit
import CoreGraphics
import Foundation
import Observation
import TootShared

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
    }

    /// Pulls whatever's changed on another device — called on launch and
    /// pull-to-refresh. No push notifications yet (see CloudSyncService's
    /// doc comment), so this is the phone-side half of how a Mac edit
    /// actually shows up here.
    func refreshFromCloud() async {
        await CloudSyncService.shared.pullRemoteChanges()
    }

    // MARK: - Mutations

    func newSticky() {
        let sticky = StickyData(
            id: UUID(), title: "To Do", day: Date(),
            items: [TodoItem()], colorID: .nextNewStickyColor(), fontID: .defaultFont,
            frame: .zero, isVisible: true)
        stickies.insert(sticky, at: 0)
        commit(sticky.id)
    }

    func setTitle(_ id: UUID, _ title: String) {
        mutate(id) { $0.title = title }
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
        }
    }

    func addItem(_ id: UUID) {
        mutate(id) { $0.items.append(TodoItem()) }
    }

    func deleteItem(_ id: UUID, _ itemID: UUID) {
        mutate(id) { $0.items.removeAll { $0.id == itemID } }
    }

    /// Every edit above funnels through here — updates `updatedAt` (so the
    /// Mac's last-write-wins comparison actually sees this as newer),
    /// persists locally, and queues the upload, mirroring exactly what
    /// `StickyModel.notifyChanged()` does on the Mac side.
    private func mutate(_ id: UUID, _ change: (inout StickyData) -> Void) {
        guard let idx = stickies.firstIndex(where: { $0.id == id }) else { return }
        change(&stickies[idx])
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
        for record in records {
            guard let data = StickyData.from(record) else { continue }
            if let idx = stickies.firstIndex(where: { $0.id == data.id }) {
                guard data.updatedAt > stickies[idx].updatedAt else { continue }
                stickies[idx] = data
            } else {
                stickies.append(data)
            }
        }
        persist()
    }

    func applyRemoteDeletions(_ ids: [UUID]) {
        stickies.removeAll { ids.contains($0.id) }
        persist()
    }
}
