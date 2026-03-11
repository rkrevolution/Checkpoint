import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {

    @Published private(set) var state: CheckpointState = .idle
    var recentCategoryIds: [String] = []

    private let maxRecentCategories = 6

    func transition(to newState: CheckpointState) {
        guard newState != state else { return }
        state = newState
    }

    func recordShownCategories(_ ids: [String]) {
        recentCategoryIds = Array((ids + recentCategoryIds).prefix(maxRecentCategories))
    }
}

enum CheckpointState: Equatable {
    case idle
    case triggered
    case presenting
    case snoozed(until: Date, count: Int)
    case paused
    case outsideHours
    case focusModeActive
}
