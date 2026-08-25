import Foundation

/// A completed task moved out of a sticky at the end of the day. Kept for
/// history and, later, analytics ("how many tasks completed").
public struct ArchivedItem: Codable, Identifiable, Equatable {
    public var id: UUID
    public var text: String
    public var stickyID: UUID
    public var stickyTitle: String
    public var completedAt: Date?
    public var archivedOn: Date
    /// The sticky's color at archive time, for the Home insight card's
    /// colored task dots. Optional so older archive files without this
    /// field still decode fine — those just show as `nil`.
    public var stickyColor: StickyColor?

    public init(id: UUID, text: String, stickyID: UUID, stickyTitle: String,
                completedAt: Date?, archivedOn: Date, stickyColor: StickyColor?) {
        self.id = id
        self.text = text
        self.stickyID = stickyID
        self.stickyTitle = stickyTitle
        self.completedAt = completedAt
        self.archivedOn = archivedOn
        self.stickyColor = stickyColor
    }
}
