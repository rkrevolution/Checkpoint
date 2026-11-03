import Foundation

/// How much check-in timing varies around the interval, as a share of the interval, so
/// labels always show the real effect ("±2 min" at a 15-min interval). Unpredictable timing
/// keeps check-ins noticeable: you can't brace for them.
enum Randomness: String, CaseIterable, Identifiable {
    case off, low, medium, high

    static let key = "randomness"
    /// The old ±seconds setting, converted once on launch (see `migrate`).
    static let legacyKey = "jitterRange"

    var id: String { rawValue }

    nonisolated var fraction: Double {
        switch self {
        case .off: return 0
        case .low: return 0.07
        case .medium: return 0.15
        case .high: return 0.25
        }
    }

    var title: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// Maximum shift either side of the interval, in seconds.
    nonisolated func seconds(for interval: TimeInterval) -> Int {
        Int((fraction * interval).rounded())
    }

    /// e.g. "Medium (±2 min)", or "Off (exactly every 15 min)".
    func label(for interval: TimeInterval) -> String {
        if self == .off {
            return "Off (exactly every \(DurationText.long(interval)))"
        }
        let s = seconds(for: interval)
        let range = s < 60 ? "±\(s) s" : "±\(Int((Double(s) / 60).rounded())) min"
        return "\(title) (\(range))"
    }

    nonisolated static func current(_ defaults: UserDefaults = .standard) -> Randomness {
        Randomness(rawValue: defaults.string(forKey: key) ?? "") ?? .medium
    }

    /// The level closest to a given share of the interval.
    nonisolated static func nearest(toFraction fraction: Double) -> Randomness {
        allCases.min { abs($0.fraction - fraction) < abs($1.fraction - fraction) }!
    }

    /// One-time conversion from the old "±seconds" jitter setting, keeping its real effect
    /// (it was capped at a quarter of the interval). Call before registering defaults.
    nonisolated static func migrate(_ defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: key) == nil,
              let legacy = defaults.object(forKey: legacyKey) as? Int else { return }
        let interval = Double(defaults.integer(forKey: "checkpointInterval"))
        let effective = interval > 0 ? min(Double(legacy), interval / 4) / interval : 0.15
        defaults.set(nearest(toFraction: effective).rawValue, forKey: key)
    }
}
