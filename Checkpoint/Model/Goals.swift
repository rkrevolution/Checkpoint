import Foundation

/// Up to three short goal lines the user keeps in view (menu, card, Today window).
/// Deliberately simple: no hierarchy, linking or tracking.
enum Goals {
    static let keys = ["goal1", "goal2", "goal3"]

    /// The non-empty goals, in order.
    nonisolated static func current(_ defaults: UserDefaults = .standard) -> [String] {
        keys.compactMap { key in
            let text = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }
    }
}
