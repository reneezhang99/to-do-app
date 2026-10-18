import Foundation

/// A single checklist line. Named `TodoItem` to avoid colliding with Swift's `Task`.
public struct TodoItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public var text: String
    public var isDone: Bool
    /// Set when the item is completed — used for archiving and sort order.
    public var completedAt: Date?
    /// Tucked under the row above it (Tab on the Mac). Only one level deep,
    /// so this is a yes/no, not a depth.
    public var isNested: Bool

    public init(id: UUID = UUID(), text: String = "", isDone: Bool = false, completedAt: Date? = nil,
                isNested: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.completedAt = completedAt
        self.isNested = isNested
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, isDone, completedAt, isNested
    }

    // Written by hand only so rows saved before nesting existed (no
    // `isNested` key at all) still load, as plain un-nested rows.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        isDone = try c.decode(Bool.self, forKey: .isDone)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        isNested = try c.decodeIfPresent(Bool.self, forKey: .isNested) ?? false
    }
}
