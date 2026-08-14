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

    public init(id: UUID, title: String, emoji: String? = nil, day: Date, items: [TodoItem],
                colorID: StickyColor, fontID: StickyFont, frame: CGRect, isVisible: Bool) {
        self.id = id
        self.title = title
        self.emoji = emoji
        self.day = day
        self.items = items
        self.colorID = colorID
        self.fontID = fontID
        self.frame = frame
        self.isVisible = isVisible
    }
}
