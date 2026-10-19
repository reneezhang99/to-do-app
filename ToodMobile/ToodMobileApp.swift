import CoreText
import SwiftUI
import TootShared
import ToodAnalytics

@main
struct ToodMobileApp: App {
    @State private var store = MobileStickyStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var foregroundPullTimer: Timer?

    init() {
        // First thing, so PostHog sees this launch too.
        Analytics.start()
        Self.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            MobileHomeView()
                .environment(store)
                .onAppear { Analytics.setPersonProperties(["mobile_sticky_count": store.stickies.count]) }
        }
        // Mirrors the Mac's `applicationDidBecomeActive` + periodic-timer
        // pair (see AppDelegate.swift) — without this, mobile only ever
        // pulled once, on cold launch, so a Mac-side edit sat unnoticed
        // until you force-quit and reopened the app. No push notifications
        // yet on either platform (see CloudSyncService's doc comment), so
        // foregrounding + a timer are what stand in for it.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Picks up the "Share anonymous usage data" switch, which
                // lives in the iPhone's Settings app under Tood.
                Analytics.applySavedChoice()
                Task { await store.refreshFromCloud() }
                foregroundPullTimer?.invalidate()
                foregroundPullTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { _ in
                    Task { @MainActor in await store.refreshFromCloud() }
                }
            default:
                // Edits wait half a second before saving (see
                // `MobileStickyStore.commit`), so write them now, before
                // the app can be suspended.
                store.savePendingNow()
                foregroundPullTimer?.invalidate()
                foregroundPullTimer = nil
            }
        }
    }

    /// Registers any fonts bundled in the app (e.g. ABC Stefan Trial, the
    /// "Cute" sticky font) so they're actually available to `Font.custom` —
    /// mirrors the Mac's `AppDelegate.registerBundledFonts()`. Without this,
    /// `Font.custom("ABCStefanTrial-Simple", size:)` silently falls back to
    /// the system font instead of erroring, so the font choice is right
    /// there in the picker but visibly does nothing when picked.
    private static func registerBundledFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil)
        else { return }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
