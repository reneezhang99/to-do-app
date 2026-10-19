import Foundation
import PostHog

/// Every product-analytics event either app sends. One list for both
/// platforms, so "sticky_created" on the Mac and on iPhone land as the same
/// event in PostHog and the dashboards can compare them side by side.
///
/// Events only ever describe *what kind* of thing happened, never what was
/// in it. No sticky titles, checklist text, or journal words go out.
public enum AnalyticsEvent: String {
    // Stickies (both platforms)
    case stickyCreated = "sticky_created"
    case stickyDeleted = "sticky_deleted"
    case stickiesReordered = "stickies_reordered"
    case stickyColorChanged = "sticky_color_changed"
    case stickyFontChanged = "sticky_font_changed"

    // Checklist rows (both platforms)
    case itemAdded = "item_added"
    case itemCompleted = "item_completed"
    case itemReopened = "item_reopened"
    case itemDeleted = "item_deleted"
    case itemNested = "item_nested"

    // Mac only
    case stickyArchived = "sticky_archived"
    case archivedStickyRestored = "archived_sticky_restored"
    case archivedStickyDeleted = "archived_sticky_deleted"
    case allStickiesDeleted = "all_stickies_deleted"
    case stickyShortcutUsed = "sticky_shortcut_used"
    case journalEntryStarted = "journal_entry_started"
    case onboardingStarted = "onboarding_started"
    case onboardingCompleted = "onboarding_completed"
    case colorPackPaywallViewed = "color_pack_paywall_viewed"
    case colorPackCheckoutClicked = "color_pack_checkout_clicked"
    case colorPackRedeemed = "color_pack_redeemed"
    case colorPackRedeemFailed = "color_pack_redeem_failed"
    case bugReportSent = "bug_report_sent"
    case announcementShown = "announcement_shown"
    case announcementDismissed = "announcement_dismissed"
    case calendarConnected = "calendar_connected"
    case calendarDisconnected = "calendar_disconnected"
    case updateCheckClicked = "update_check_clicked"
}

/// A thin wrapper around PostHog. The apps call this instead of PostHog
/// directly, so turning analytics off (or swapping tools later) only
/// touches one file.
public enum Analytics {
    // The project token is meant to ship inside apps: it can only send
    // events in, not read anything out. So it lives here, not in Secrets.swift.
    private static let projectToken = "phc_o4hxS7Sfb8BBpjyyyLCLCBnLDgAy5gzKn7g2tDSHMBxk"
    private static let host = "https://us.i.posthog.com"
    private static let enabledKey = "today.analyticsEnabled"

    /// The Settings switch. On unless someone turns it off.
    public static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue { PostHogSDK.shared.optIn() } else { PostHogSDK.shared.optOut() }
        }
    }

    /// Call once, as early in launch as possible, so PostHog's own
    /// "Application Opened" / "Application Installed" / "Application Updated"
    /// events catch this launch too.
    public static func start() {
        let config = PostHogConfig(projectToken: projectToken, host: host)
        // Person profiles let retention and "how many stickies do people
        // keep" work per person. People stay anonymous: we never call identify.
        config.personProfiles = .always
        // SwiftUI screens would show up as "UIHostingController" noise.
        // Each app names its screens itself with `screen(_:)` instead.
        config.captureScreenViews = false
        // Crashes get saved and sent as `$exception` on the next launch.
        config.errorTrackingConfig.autoCapture = true
        config.optOut = !isEnabled
        // Stamp these on every event, so every chart can split by them.
        // Done here, not with `register(_:)`, because PostHog's own
        // "Application Installed" fires during setup, before `register` could run.
        config.setBeforeSend { event in
            event.properties["platform"] = platform
            // Debug builds still send, so you can watch events arrive while
            // testing, but the dashboards filter them out.
            event.properties["build_type"] = isDebugBuild ? "debug" : "release"
            return event
        }
        #if os(iOS)
        config.surveys = false
        #endif
        PostHogSDK.shared.setup(config)
    }

    /// The iPhone's switch lives in the Settings app, which flips the saved
    /// value behind Tood's back. Call this when the app comes back to the
    /// front so a change there takes effect right away.
    public static func applySavedChoice() {
        if isEnabled { PostHogSDK.shared.optIn() } else { PostHogSDK.shared.optOut() }
    }

    public static func track(_ event: AnalyticsEvent, _ properties: [String: Any] = [:]) {
        PostHogSDK.shared.capture(event.rawValue, properties: properties.isEmpty ? nil : properties)
    }

    /// Which window/screen someone is looking at, for paths and "what do
    /// people actually open" charts.
    public static func screen(_ name: String) {
        PostHogSDK.shared.screen(name)
    }

    /// Facts about the person's setup (how many stickies, which settings),
    /// so charts can split by "people with calendar on" and so on.
    public static func setPersonProperties(_ properties: [String: Any]) {
        PostHogSDK.shared.setPersonProperties(userPropertiesToSet: properties)
    }

    private static var platform: String {
        #if os(macOS)
        return "macOS"
        #else
        return "iOS"
        #endif
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
