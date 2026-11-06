import Foundation

/// The check-in intervals offered in Settings, in minutes.
nonisolated enum IntervalOptions {
    static let minutes = [1, 2, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120]

    /// The listed option closest to `mins`, so an unlisted value (e.g. from a launch argument)
    /// shows as the nearest choice without being changed.
    static func nearest(to mins: Int) -> Int {
        minutes.min { abs($0 - mins) < abs($1 - mins) } ?? 45
    }

    static func label(_ mins: Int) -> String {
        switch mins {
        case 1: return "1 min"
        case 60: return "1 hour"
        case 90: return "1.5 hours"
        case 120: return "2 hours"
        default: return "\(mins) min"
        }
    }
}
