import CloudKit
import Foundation

/// Caches each synced record's CloudKit "system fields" (record type, zone,
/// and — critically — its change tag) on disk, keyed by record name.
///
/// Without this, every save would build a bare `CKRecord(recordType:recordID:)`
/// with no change tag, which reads to CloudKit as "I don't know what's
/// there already" rather than "here's an edit to the version I last saw" —
/// every update past the first would come back as a `.serverRecordChanged`
/// conflict even when nothing else touched the record. Keeping the last
/// system fields we've seen (from a fetch or a successful save) and
/// stamping them onto the record we're about to send fixes that.
@available(macOS 14.0, iOS 17.0, *)
final class RecordMetadataStore {
    private var cache: [String: Data] = [:]
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("com.renee.Today", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("cloud_sync_records.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Data].self, from: data) {
            cache = decoded
        }
    }

    /// Remembers `record`'s system fields for next time it's saved.
    func store(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        cache[record.recordID.recordName] = coder.encodedData
        persist()
    }

    func remove(_ recordID: CKRecord.ID) {
        cache.removeValue(forKey: recordID.recordName)
        persist()
    }

    /// Returns `record` with its change tag set to whatever we last saw for
    /// that record name, if anything — unchanged if this is a record we've
    /// never synced before (a genuinely new save, which is fine as-is).
    func applyCachedSystemFields(to record: CKRecord) -> CKRecord {
        guard let data = cache[record.recordID.recordName],
              let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return record }
        coder.requiresSecureCoding = true
        guard let cached = CKRecord(coder: coder) else { return record }
        // Copy the fields we actually set onto the record whose system
        // fields (change tag) we trust, rather than the other way around —
        // `cached` carries stale field values from whenever it was last
        // fetched/saved.
        for key in record.allKeys() {
            cached[key] = record[key]
        }
        return cached
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
