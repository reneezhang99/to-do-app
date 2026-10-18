import AppKit
import SwiftUI
import CoreText
import Sparkle
import TootShared
import ToodAnalytics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var manager: StickyManager!
    private var journal: JournalStore!
    private var statusMenu: StatusMenuController!

    /// Sparkle's own standard UI (a quiet "update available" prompt, not a
    /// custom one) — background checks daily (SUScheduledCheckInterval),
    /// downloads on demand, never installs without asking first.
    private(set) var updaterController: SPUStandardUpdaterController!

    private var homeWindow: HostedWindowController<HomeView>?
    private var settingsWindow: HostedWindowController<SettingsView>?
    private var onboardingWindow: HostedWindowController<OnboardingView>?
    private var introWindow: HostedWindowController<IntroFallView>?
    private var reportBugWindow: HostedWindowController<ReportBugView>?

    private var cloudPullTimer: Timer?
    private var applicationShortcutMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular app: Dock icon visible, matches LSUIElement=false in
        // Info.plist. (This call is what actually governs it at runtime —
        // Info.plist's LSUIElement alone isn't enough once the app is
        // already running.)
        NSApp.setActivationPolicy(.regular)

        // The whole design (cream paper, dark ink text) is deliberately
        // light-only — there's no dark palette for it. Without this, macOS
        // Dark Mode flips every semantic/system color (.primary, .secondary,
        // system backgrounds, etc.) to their dark-mode values while the
        // hardcoded cream/paper backgrounds stay put, producing white text
        // on a light background. Forcing light appearance for the whole app
        // keeps it looking the same regardless of the system setting.
        NSApp.appearance = NSAppearance(named: .aqua)

        registerBundledFonts()
        manager = StickyManager()
        journal = JournalStore()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        statusMenu = StatusMenuController(manager: manager, appDelegate: self)
        manager.restoreAll()
        setUpCloudSync()
        reportSetupToAnalytics()

        GlobalHotKeyManager.shared.onShowSticky = { [weak self] in self?.manager.showActiveSticky() }
        GlobalHotKeyManager.shared.onNewSticky = { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.manager.newSticky()
        }
        GlobalHotKeyManager.shared.reregister()
        AnnouncementService.shared.checkForAnnouncement()

        // App-local, not a true system-wide hotkey (unlike the two above,
        // registered via GlobalHotKeyManager) — Control-1…0 only makes sense
        // while Tood already has focus, jumping between stickies that are
        // already open, so it doesn't need Accessibility/Input Monitoring
        // permission or risk colliding with another app's shortcuts.
        applicationShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, AppSettings.shared.onboardingCompleted else { return event }
            guard event.modifierFlags.intersection([.command, .shift, .control, .option]) == [.control],
                  let key = event.charactersIgnoringModifiers?.lowercased(),
                  let index = StickySelectionShortcut.stickyIndex(forKeyEquivalent: key),
                  self.manager.focusSticky(atShortcutIndex: index)
            else { return event }
            Analytics.track(.stickyShortcutUsed, ["slot": index + 1])
            return nil
        }

        if !AppSettings.shared.onboardingCompleted {
            // Don't let real floating stickies (a true first run's
            // auto-created one, or any left over from previous use while
            // testing) appear behind/around the onboarding windows — the
            // "Sticky" step reveals its one sticky deliberately, and
            // `onFinish` below reveals the rest once onboarding is done.
            manager.hideAll()
            showIntro()
        } else {
            // A normal launch (double-click in Finder, Spotlight, etc.) —
            // without this, an .accessory app with no Dock icon has no
            // window to show, so it'd silently do nothing visible at all.
            showHome()
        }
    }

    // Re-launching the app while it's already running (e.g. opening it
    // again from Finder/Spotlight) brings Home back along with the notes.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Guard against the Dock icon (now always visible) being clicked
        // mid-onboarding — that shouldn't reveal every sticky and Home
        // before onboarding's own "Sticky" step gets to do that itself.
        guard AppSettings.shared.onboardingCompleted else { return true }
        manager.showAll()
        showHome()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.saveNow()
    }

    // Foregrounding is the closest thing to a "the user is here, might as
    // well check" signal available without the aps-environment push
    // entitlement (see CloudSyncService's doc comment) — this plus the
    // periodic timer are what stand in for it for now.
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await CloudSyncService.shared.pullRemoteChanges() }
    }

    // MARK: - iCloud sync

    /// Registers each local store with `CloudSyncService`, backfills
    /// anything created before this feature shipped, and starts a
    /// lightweight periodic pull. No push notifications yet, so this and
    /// `applicationDidBecomeActive` are what keep a second device's changes
    /// from sitting unnoticed indefinitely.
    private func setUpCloudSync() {
        CloudSyncService.shared.register(manager, for: .sticky)
        CloudSyncService.shared.register(journal, for: .journalEntry)
        CloudSyncService.shared.register(ArchivedStickySyncAdapter(service: manager.stickyArchive), for: .archivedSticky)
        CloudSyncService.shared.register(ArchivedItemSyncAdapter(service: manager.archive), for: .archivedItem)

        performInitialCloudBackfillIfNeeded()

        Task { await CloudSyncService.shared.pullRemoteChanges() }

        cloudPullTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { _ in
            Task { @MainActor in await CloudSyncService.shared.pullRemoteChanges() }
        }
    }

    /// The first time this ships, nothing existing has ever been queued for
    /// upload — everything from here on gets queued the moment it changes
    /// (see each store's own `CloudSyncService.shared.save(...)` calls), but
    /// that never fires for a sticky that was created weeks ago and hasn't
    /// been touched since. One-time queue of everything already on disk
    /// closes that gap; the UserDefaults flag means it only ever runs once
    /// per device, not on every launch.
    private func performInitialCloudBackfillIfNeeded() {
        let key = "today.cloudSyncDidBackfill"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        for sticky in manager.stickyList() {
            CloudSyncService.shared.save(id: sticky.id, collection: .sticky)
        }
        for entry in journal.entries {
            CloudSyncService.shared.save(id: entry.id, collection: .journalEntry)
        }
        for archived in manager.stickyArchive.load() {
            CloudSyncService.shared.save(id: archived.id, collection: .archivedSticky)
        }
        for item in manager.archive.load() {
            CloudSyncService.shared.save(id: item.id, collection: .archivedItem)
        }

        UserDefaults.standard.set(true, forKey: key)
        Task { await CloudSyncService.shared.pushLocalChanges() }
    }

    /// A snapshot of how this person has Tood set up, refreshed every
    /// launch. Lets charts split by things like "has calendar connected".
    private func reportSetupToAnalytics() {
        let settings = AppSettings.shared
        Analytics.setPersonProperties([
            "open_sticky_count": manager.order.count,
            "archived_sticky_count": manager.archivedStickies.count,
            "journal_entry_count": journal.entries.count,
            "calendar_connected": GoogleAuthService.shared.isConnected,
            "color_packs_owned": ColorPackStore.shared.unlockedPackIDs.count,
            "launch_at_login": settings.launchAtLogin,
            "journal_location_enabled": settings.journalLocationEnabled,
            "close_behavior": settings.closeBehavior.rawValue,
            "completion_animations_enabled": settings.completionAnimationsEnabled,
            "onboarding_completed": settings.onboardingCompleted,
        ])
    }

    // MARK: - Windows

    func showHome() {
        if homeWindow == nil {
            homeWindow = HostedWindowController(
                title: "Tood",
                size: NSSize(width: 900, height: 640),
                hidesTitleBar: true,
                content: HomeView(manager: manager, journal: journal)
            )
        }
        homeWindow?.present()
        Analytics.screen("Home")
        // The periodic refresh in AgendaTimeline can be up to 5 minutes
        // stale — an immediate one here makes reopening Home feel current
        // right away instead of waiting for the next tick.
        Task { await GoogleCalendarService.shared.refreshToday() }
    }

    /// The status menu's "Check for Updates…" — same feed/UI Sparkle's own
    /// background checks use, just triggered on demand.
    func checkForUpdates() {
        Analytics.track(.updateCheckClicked)
        updaterController.checkForUpdates(nil)
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = HostedWindowController(
                title: "Settings",
                size: NSSize(width: 460, height: 480),
                resizable: false,
                content: SettingsView(settings: AppSettings.shared)
            )
        }
        settingsWindow?.present()
        Analytics.screen("Settings")
    }

    /// Fresh window every time (unlike Settings/Home, which stay around) —
    /// this is a one-shot form, not persistent state, so reopening it later
    /// should start blank rather than showing whatever was left over from
    /// the last report.
    func showReportBug() {
        let controller = HostedWindowController(
            title: "Report a Bug",
            size: NSSize(width: 420, height: 400),
            resizable: false,
            content: ReportBugView(onDone: { [weak self] in
                self?.reportBugWindow?.close()
                self?.reportBugWindow = nil
            })
        )
        reportBugWindow = controller
        controller.present()
        Analytics.screen("Report Bug")
    }

    private func showIntro() {
        let controller = HostedWindowController(
            title: "Tood",
            size: NSSize(width: 640, height: 520),
            resizable: false,
            hidesTitleBar: true,
            content: IntroFallView(onContinue: { [weak self] in
                self?.introWindow?.close()
                self?.introWindow = nil
                self?.showOnboarding()
            })
        )
        introWindow = controller
        controller.present()
        Analytics.screen("Intro")
    }

    private func showOnboarding() {
        let controller = HostedWindowController(
            title: "Welcome to Tood",
            size: NSSize(width: 640, height: 520),
            resizable: false,
            hidesTitleBar: true,
            content: OnboardingView(manager: manager, settings: AppSettings.shared, onFinish: { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                self?.manager.showAll()
                self?.showHome()
            }, onExitToIntro: { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                self?.showIntro()
            })
        )
        onboardingWindow = controller
        controller.present()
        Analytics.screen("Onboarding")
        Analytics.track(.onboardingStarted)
    }

    /// Register any fonts bundled in the app (e.g. ABC Stefan Trial) so they
    /// work regardless of what's installed on the machine.
    private func registerBundledFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil)
        else { return }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
