import SwiftUI

/// Font options for a sticky's body text. The big "To Do" title always uses
/// Helvetica Neue Medium regardless of this choice.
///
/// Portability note: "Bradley Hand" is a macOS system font, not guaranteed
/// present on iOS — `.body(_:)` will fall back to whatever `Font.custom`
/// does when the face is missing (the system font, still functional, just
/// not the intended look). Worth a real fix once the iOS UI is underway.
public enum StickyFont: String, CaseIterable, Codable, Identifiable {
    case helvetica   // "Basic" — the system font (SF Pro). Rawvalue kept as
                     // "helvetica" for compatibility with already-saved stickies.
    case menlo       // "Technical" — monospaced
    case stefan      // "Cute" — ABC Stefan Trial (Simple), bundled
    case bradley     // "Handwritten" — Bradley Hand

    /// Same idea as `StickyColor`'s: a font from a newer version reads as
    /// Basic instead of making the whole sticky unreadable.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StickyFont(rawValue: raw) ?? .helvetica
    }

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .helvetica: return "Basic"
        case .menlo:     return "Technical"
        case .stefan:    return "Cute"
        case .bradley:   return "Handwritten"
        }
    }

    /// The exact font name used with `Font.custom` (PostScript names where it
    /// matters, so the correct face renders rather than a synthesized one).
    /// Unused for `.helvetica`, which renders via `Font.system` instead.
    public var fontName: String {
        switch self {
        case .helvetica: return "HelveticaNeue"
        case .menlo:     return "Menlo"
        case .stefan:    return "ABCStefanTrial-Simple"
        case .bradley:   return "Bradley Hand"
        }
    }

    /// Body font at a given size. The big "To Do" title always stays
    /// Helvetica Neue regardless of this choice (set directly in the view).
    public func body(_ size: CGFloat) -> Font {
        if self == .helvetica {
            return .system(size: size + sizeAdjustment) // SF Pro
        }
        return Font.custom(fontName, size: size + sizeAdjustment)
    }

    /// Some faces read small at the same nominal point size (smaller
    /// x-height than System/Menlo) — nudge them up so all four options look
    /// the same visual size next to each other, e.g. in the Settings picker.
    public var sizeAdjustment: CGFloat {
        switch self {
        case .bradley: return 3
        case .stefan: return 3
        default: return 0
        }
    }
}

extension StickyFont {
    private static let defaultsKey = "today.defaultStickyFont"

    /// The font new stickies are created with. Set from the status-bar menu.
    public static var defaultFont: StickyFont {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(StickyFont.init) ?? .helvetica }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}
