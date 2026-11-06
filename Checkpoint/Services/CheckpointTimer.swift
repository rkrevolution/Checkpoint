import Foundation
import os.log

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "CheckpointTimer")

@MainActor
final class CheckpointTimer {

    var onFire: (() -> Void)?
    /// Called with each scheduled fire date, so it can be remembered across relaunches.
    var onSchedule: ((Date) -> Void)?

    private var timer: DispatchSourceTimer?
    private var _nextFireDate: Date?
    private let settings: AppSettings

    /// - Parameter settings: where the randomness setting is read (a throwaway suite in tests)
    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    var nextFireDate: Date? {
        guard timer != nil else { return nil }
        return _nextFireDate
    }

    /// - Parameter firstFireIn: wait before the first check-in, e.g. to keep a schedule across a
    ///   relaunch; later check-ins use the interval with jitter as usual.
    func start(interval: TimeInterval, firstFireIn: TimeInterval? = nil) {
        log.notice("start: baseInterval=\(Int(interval))s")
        stop()
        scheduleNext(baseInterval: interval, delay: firstFireIn.map { Int($0.rounded()) })
    }

    private func scheduleNext(baseInterval: TimeInterval, delay: Int? = nil) {
        timer?.cancel()

        let jitterRange = settings.randomness.seconds(for: baseInterval)
        let jitter = jitterRange > 0 ? Int.random(in: -jitterRange...jitterRange) : 0
        let actual = delay ?? max(60, Int(baseInterval) + jitter) // never less than 1 min

        let fireDate = Date().addingTimeInterval(TimeInterval(actual))
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        log.notice("━━━ NEXT CHECKPOINT SCHEDULED ━━━")
        log.notice("  Base interval: \(Int(baseInterval))s (\(Int(baseInterval)/60)min)")
        log.notice("  Jitter applied: \(jitter > 0 ? "+" : "")\(jitter)s")
        log.notice("  Actual wait: \(actual)s (\(actual/60)min \(actual%60)s)")
        log.notice("  Will fire at: \(formatter.string(from: fireDate))")

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + .seconds(actual))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            log.notice("Timer FIRED")
            self.onFire?()
            self.scheduleNext(baseInterval: baseInterval)
        }
        _nextFireDate = fireDate
        source.resume()
        timer = source
        onSchedule?(fireDate)
    }

    /// How long to wait for the first check-in after a launch, given when the next one was due
    /// before the app quit. Keeps a pending check-in instead of restarting the countdown; one that
    /// came due while the app was closed shows shortly after launch. Nil means start normally.
    nonisolated static func resumeDelay(savedDue: Date?, now: Date, interval: TimeInterval) -> TimeInterval? {
        guard let savedDue else { return nil }
        let remaining = savedDue.timeIntervalSince(now)
        if remaining < -interval { return nil }            // missed long ago (e.g. overnight): start fresh
        if remaining <= 0 { return 90 }                    // missed while closed: check in soon
        if remaining > interval * 1.5 { return nil }       // stale or interval changed: start fresh
        return max(30, remaining)
    }

    func stop() {
        log.notice("stop")
        timer?.cancel()
        timer = nil
        _nextFireDate = nil
    }

    func restart(interval: TimeInterval) {
        log.notice("restart: interval=\(Int(interval))s")
        stop()
        start(interval: interval)
    }
}
