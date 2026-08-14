import Foundation

/// A whole sticky, archived when the user picks "Archive" over "Delete"
/// from the close confirmation — a full snapshot kept as a browsable
/// memory of finished stickies.
public struct ArchivedSticky: Codable, Identifiable, Equatable {
    public var id: UUID
    public var data: StickyData
    public var archivedAt: Date

    public init(id: UUID, data: StickyData, archivedAt: Date) {
        self.id = id
        self.data = data
        self.archivedAt = archivedAt
    }
}
