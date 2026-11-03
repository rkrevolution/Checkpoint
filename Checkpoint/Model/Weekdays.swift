import Foundation

/// Calendar weekday numbers (Sunday = 1 … Saturday = 7), as stored in `skipWeekdays`.
enum Weekdays {
    /// Weekdays in the order the user's calendar shows them (e.g. Monday first).
    nonisolated static func ordered(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    nonisolated static func shortName(_ weekday: Int, calendar: Calendar = .current) -> String {
        calendar.veryShortWeekdaySymbols[weekday - 1]
    }

    /// Returns the sorted skip list with `weekday` added or removed.
    nonisolated static func setSkipped(_ weekday: Int, skipped: Bool, in list: [Int]) -> [Int] {
        var set = Set(list)
        if skipped { set.insert(weekday) } else { set.remove(weekday) }
        return set.sorted()
    }
}
