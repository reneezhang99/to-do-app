import Foundation
import WidgetKit

/// Shares the handful of stickies the Home Screen widget needs across the
/// App Group container — the widget extension runs in its own sandbox and
/// process, completely separate from the main app's private storage, so
/// this (not the app's own on-disk JSON) is the only thing it can actually
/// see.
///
/// Mobile-only in practice (there's no Mac widget), but lives here rather
/// than in `ToodMobile` because `StickyData` does — keeping the read and
/// write sides next to the type they share is worth the platform-neutral
/// home even though only one side is ever used today.
public enum WidgetSnapshotStore {
    public static let appGroupID = "group.com.renee.Today"
    private static let key = "widget.stickies"

    /// Called by the app whenever its sticky list changes. Keeps only what
    /// the widget could ever actually show — a handful, most-prominent
    /// first — rather than mirroring the full list into a second copy.
    public static func write(_ stickies: [StickyData]) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let top = Array(stickies.prefix(6))
        guard let data = try? JSONEncoder().encode(top) else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    public static func read() -> [StickyData] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: key),
              let stickies = try? JSONDecoder().decode([StickyData].self, from: data)
        else { return [] }
        return stickies
    }
}
