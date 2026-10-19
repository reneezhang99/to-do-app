import Foundation
import AppKit

/// Fires an (idempotent) rollover at local midnight, plus catch-up on launch
/// and on wake/clock-change. Robust to sleep and DST because it always
/// recomputes the next boundary rather than adding 24h.
@MainActor
final class RolloverScheduler {
    private let onRollover: () async -> Void
    private var timer: Timer?
    private let defaultsKey = "today.lastRolloverDay"
    /// The rollover waits on an iCloud pull now, so wake and the midnight
    /// timer could otherwise both start one before the first finishes.
    private var isRunning = false

    init(onRollover: @escaping () async -> Void) {
        self.onRollover = onRollover
    }

    func start() {
        // Catch up if the day changed while we were closed/asleep.
        runIfNeeded()
        scheduleNextMidnight()

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(wakeOrClockChanged),
                       name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(wakeOrClockChanged),
            name: .NSSystemClockDidChange, object: nil)
    }

    @objc private func wakeOrClockChanged() {
        runIfNeeded()
        scheduleNextMidnight()
    }

    /// Runs the rollover only if we haven't already rolled over today.
    private func runIfNeeded() {
        guard !isRunning else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let last = (UserDefaults.standard.object(forKey: defaultsKey) as? Date)
            .map { Calendar.current.startOfDay(for: $0) }
        if last == today { return }
        isRunning = true
        Task {
            await onRollover()
            // Marked done only after it actually ran, so quitting halfway
            // through the iCloud pull doesn't skip a whole day's cleanup.
            UserDefaults.standard.set(today, forKey: defaultsKey)
            isRunning = false
        }
    }

    private func scheduleNextMidnight() {
        timer?.invalidate()
        // A few seconds past midnight to avoid boundary ambiguity.
        guard let next = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 5),
            matchingPolicy: .nextTime) else { return }

        let t = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.runIfNeeded()
                self?.scheduleNextMidnight() // never assume +24h
            }
        }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
