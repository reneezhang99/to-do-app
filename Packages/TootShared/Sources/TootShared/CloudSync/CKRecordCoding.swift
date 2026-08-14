import CloudKit
import Foundation

/// Every synced type stores itself as a single JSON blob in one CKRecord
/// field (`payload`) rather than mapping each property to its own field.
/// These shapes already round-trip through JSON for local persistence
/// (`PersistenceService`, `ArchiveService`, etc.), so this reuses exactly
/// that path instead of a second encoding scheme that could drift out of
/// sync with it. A couple of plain top-level fields get mirrored alongside
/// the blob purely so records are legible in the CloudKit Dashboard.
@available(macOS 14.0, iOS 17.0, *)
enum CKRecordCoding {
    static func encodePayload<T: Encodable>(_ value: T, into record: CKRecord) {
        guard let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else { return }
        record["payload"] = json as CKRecordValue
    }

    static func decodePayload<T: Decodable>(_ type: T.Type, from record: CKRecord) -> T? {
        guard let json = record["payload"] as? String,
              let data = json.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
