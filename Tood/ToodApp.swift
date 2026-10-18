import SwiftUI
import ToodAnalytics

@main
struct ToodApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Before the app delegate runs, so PostHog sees this launch too.
        Analytics.start()
    }

    var body: some Scene {
        // No WindowGroup — the sticky windows are created imperatively by the
        // AppDelegate/StickyManager. `Settings` is an empty scene that keeps
        // SwiftUI's App lifecycle happy without auto-opening a window.
        Settings {
            EmptyView()
        }
    }
}
