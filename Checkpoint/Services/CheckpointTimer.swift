import Foundation
import os.log

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "CheckpointTimer")

@MainActor
final class CheckpointTimer {

    var onFire: (() -> Void)?

    private var timer: DispatchSourceTimer?
    private var _nextFireDate: Date?

    var nextFireDate: Date? {
        guard timer != nil else { return nil }
        return _nextFireDate
    }

    func start(interval: TimeInterval) {
        log.notice("start: baseInterval=\(Int(interval))s")
        stop()
        scheduleNext(baseInterval: interval)
    }

    private func scheduleNext(baseInterval: TimeInterval) {
        timer?.cancel()

        let jitterRange = Self.effectiveJitterRange(
            setting: UserDefaults.standard.integer(forKey: "jitterRange"),
            baseInterval: baseInterval
        )
        let jitter = jitterRange > 0 ? Int.random(in: -jitterRange...jitterRange) : 0
        let actual = max(60, Int(baseInterval) + jitter) // never less than 1 min

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
    }

    /// Jitter is capped at a quarter of the interval so short intervals aren't dominated by randomness.
    nonisolated static func effectiveJitterRange(setting: Int, baseInterval: TimeInterval) -> Int {
        max(0, min(setting, Int(baseInterval) / 4))
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
