import Foundation

/// A single checklist line. Named `TodoItem` to avoid colliding with Swift's `Task`.
public struct TodoItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public var text: String
    public var isDone: Bool
    /// Set when the item is completed — used for archiving and sort order.
    public var completedAt: Date?

    public init(id: UUID = UUID(), text: String = "", isDone: Bool = false, completedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.completedAt = completedAt
    }
}
