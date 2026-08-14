import CloudKit
import Foundation

// Each syncable type round-trips through a single JSON `payload` field (see
// `CKRecordCoding`) plus a `title`/`archivedAt`/etc. field mirrored
// alongside purely so the record reads as something recognizable in the
// CloudKit Dashboard — decoding always goes through the payload, never
// those mirrored fields.

@available(macOS 14.0, iOS 17.0, *)
extension StickyData {
    public func toRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: SyncCollection.sticky.rawValue,
                               recordID: CKRecord.ID(recordName: "\(SyncCollection.sticky.rawValue)_\(id.uuidString)", zoneID: zoneID))
        CKRecordCoding.encodePayload(self, into: record)
        record["title"] = title as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
        return record
    }

    public static func from(_ record: CKRecord) -> StickyData? {
        CKRecordCoding.decodePayload(StickyData.self, from: record)
    }
}

@available(macOS 14.0, iOS 17.0, *)
extension ArchivedSticky {
    public func toRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: SyncCollection.archivedSticky.rawValue,
                               recordID: CKRecord.ID(recordName: "\(SyncCollection.archivedSticky.rawValue)_\(id.uuidString)", zoneID: zoneID))
        CKRecordCoding.encodePayload(self, into: record)
        record["title"] = data.title as CKRecordValue
        record["archivedAt"] = archivedAt as CKRecordValue
        return record
    }

    public static func from(_ record: CKRecord) -> ArchivedSticky? {
        CKRecordCoding.decodePayload(ArchivedSticky.self, from: record)
    }
}

@available(macOS 14.0, iOS 17.0, *)
extension ArchivedItem {
    public func toRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: SyncCollection.archivedItem.rawValue,
                               recordID: CKRecord.ID(recordName: "\(SyncCollection.archivedItem.rawValue)_\(id.uuidString)", zoneID: zoneID))
        CKRecordCoding.encodePayload(self, into: record)
        record["text"] = text as CKRecordValue
        record["archivedOn"] = archivedOn as CKRecordValue
        return record
    }

    public static func from(_ record: CKRecord) -> ArchivedItem? {
        CKRecordCoding.decodePayload(ArchivedItem.self, from: record)
    }
}

@available(macOS 14.0, iOS 17.0, *)
extension JournalEntry {
    public func toRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: SyncCollection.journalEntry.rawValue,
                               recordID: CKRecord.ID(recordName: "\(SyncCollection.journalEntry.rawValue)_\(id.uuidString)", zoneID: zoneID))
        CKRecordCoding.encodePayload(self, into: record)
        record["day"] = day as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
        return record
    }

    public static func from(_ record: CKRecord) -> JournalEntry? {
        CKRecordCoding.decodePayload(JournalEntry.self, from: record)
    }
}
