import Foundation

/// Plain `Codable` snapshot of a sticky. Kept separate from any runtime
/// `@Observable` wrapper (which stays platform-specific — see
/// `StickyModel` in the macOS app) because the Observation macro doesn't
/// encode cleanly, and because the runtime wrapper's AppKit-focus-bridging
/// design is Mac-specific even where its imports aren't.
public struct StickyData: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    /// Leftover from a short-lived separate icon field — some stickies were
    /// saved with the emoji split out into this key instead of being the
    /// title's first character. Never written anymore (the owning runtime
    /// model merges it straight back into `title` on load and drops it),
    /// kept here only so those already-split saves decode losslessly
    /// instead of silently dropping their icon.
    public var emoji: String?
    public var day: Date
    public var items: [TodoItem]
    public var colorID: StickyColor
    public var fontID: StickyFont
    public var frame: CGRect
    public var isVisible: Bool
    /// When this sticky last actually changed — added for iCloud sync's
    /// last-write-wins conflict resolution (whichever device's copy is
    /// newer here wins when the same sticky was edited on two devices
    /// before either saw the other's change). Decodes to "now" for
    /// already-saved stickies from before this field existed, since we
    /// genuinely don't know when they last changed and treating them as
    /// current is the safer guess for a field that only matters once sync
    /// is involved.
    public var updatedAt: Date

    public init(id: UUID, title: String, emoji: String? = nil, day: Date, items: [TodoItem],
                colorID: StickyColor, fontID: StickyFont, frame: CGRect, isVisible: Bool,
                updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.emoji = emoji
        self.day = day
        self.items = items
        self.colorID = colorID
        self.fontID = fontID
        self.frame = frame
        self.isVisible = isVisible
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, emoji, day, items, colorID, fontID, frame, isVisible, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        day = try c.decode(Date.self, forKey: .day)
        items = try c.decode([TodoItem].self, forKey: .items)
        colorID = try c.decode(StickyColor.self, forKey: .colorID)
        fontID = try c.decode(StickyFont.self, forKey: .fontID)
        frame = try c.decode(CGRect.self, forKey: .frame)
        isVisible = try c.decode(Bool.self, forKey: .isVisible)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(emoji, forKey: .emoji)
        try c.encode(day, forKey: .day)
        try c.encode(items, forKey: .items)
        try c.encode(colorID, forKey: .colorID)
        try c.encode(fontID, forKey: .fontID)
        try c.encode(frame, forKey: .frame)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}
