import Foundation

/// One stretch of work on an objective. Active time excludes time away
/// (sleep, lock, screensaver) and time the app wasn't running.
struct ObjectiveSession: Codable, Equatable, Identifiable {
    let id: UUID
    let objective: String
    var ifThenPlan: String?
    let startedAt: Date
    var endedAt: Date?
    var awaySeconds: TimeInterval
    /// Set while the user is away right now.
    var awaySince: Date?

    nonisolated func activeSeconds(at now: Date) -> TimeInterval {
        let end = endedAt ?? now
        var away = awaySeconds
        if let since = awaySince {
            away += max(0, end.timeIntervalSince(since))
        }
        return max(0, end.timeIntervalSince(startedAt) - away)
    }
}

/// Human-readable durations for the card, menu bar and summaries.
enum DurationText {
    /// "under 1 min", "45 min", "2 h", "2 h 40 min"
    nonisolated static func long(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "under 1 min" }
        let (h, m) = (minutes / 60, minutes % 60)
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Compact form for the menu bar: "<1m", "45m", "2h", "2h40m"
    nonisolated static func short(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "<1m" }
        let (h, m) = (minutes / 60, minutes % 60)
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }
}
