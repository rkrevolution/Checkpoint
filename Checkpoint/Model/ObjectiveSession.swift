import Foundation

/// One stretch of work on an objective. Active time excludes time away
/// (sleep, lock, screensaver) and time the app wasn't running.
nonisolated struct ObjectiveSession: Codable, Equatable, Identifiable {
    let id: UUID
    let objective: String
    var ifThenPlan: String?
    /// The user's guess at how long this will take (#11)
    var estimateMinutes: Int? = nil
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

extension ObjectiveSession {
    /// "1 h 20 min of ~1 h · since 9:22", or "1 h 20 min · since 9:22" without an estimate.
    nonisolated func progressText(at now: Date) -> String {
        let active = DurationText.long(activeSeconds(at: now))
        let since = startedAt.formatted(date: .omitted, time: .shortened)
        if let estimateMinutes {
            return "\(active) of ~\(DurationText.long(Double(estimateMinutes) * 60)) · since \(since)"
        }
        return "\(active) · since \(since)"
    }

    nonisolated func isOverEstimate(at now: Date) -> Bool {
        guard let estimateMinutes else { return false }
        return activeSeconds(at: now) > Double(estimateMinutes) * 60
    }
}

/// Time per objective across stretches (switching back to a task adds to the same total).
enum ObjectiveTotals {
    struct Total: Equatable {
        let objective: String
        let seconds: TimeInterval
        let stretches: Int
    }

    /// Totals by objective name, longest first.
    nonisolated static func byObjective(_ sessions: [ObjectiveSession], at now: Date) -> [Total] {
        var order: [String] = []
        var seconds: [String: TimeInterval] = [:]
        var counts: [String: Int] = [:]
        for session in sessions {
            if seconds[session.objective] == nil { order.append(session.objective) }
            seconds[session.objective, default: 0] += session.activeSeconds(at: now)
            counts[session.objective, default: 0] += 1
        }
        return order
            .map { Total(objective: $0, seconds: seconds[$0]!, stretches: counts[$0]!) }
            .sorted { $0.seconds > $1.seconds }
    }
}

/// Estimate vs actual (#11): how much longer (or shorter) tasks took than the user guessed.
enum EstimateStats {
    /// Total actual time divided by total estimated time, over sessions that have an estimate
    /// and at least a minute of work. 1.4 means tasks took 40% longer than estimated.
    nonisolated static func ratio(_ sessions: [ObjectiveSession], at now: Date) -> Double? {
        let estimated = sessions.filter { ($0.estimateMinutes ?? 0) > 0 && $0.activeSeconds(at: now) >= 60 }
        let estimate = estimated.reduce(0.0) { $0 + Double($1.estimateMinutes!) * 60 }
        let actual = estimated.reduce(0.0) { $0 + $1.activeSeconds(at: now) }
        guard estimate > 0 else { return nil }
        return actual / estimate
    }

    /// "took 1.4× your estimates", "matched your estimates", "took 0.7× your estimates"
    nonisolated static func describe(_ ratio: Double) -> String {
        if abs(ratio - 1) < 0.1 { return "matched your estimates" }
        return String(format: "took %.1f× your estimates", ratio)
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
