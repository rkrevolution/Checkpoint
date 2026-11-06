import Foundation
import os.log

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "ScheduleManager")

@MainActor
final class ScheduleManager {

    private let settings: AppSettings

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    func shouldFire(at date: Date = Date()) -> Bool {
        let enabled = settings.checkInsEnabled
        guard enabled else {
            log.notice("shouldFire=false: checkpointsEnabled=false")
            return false
        }
        guard isWithinActiveHours(at: date) else {
            log.notice("shouldFire=false: outside active hours")
            return false
        }
        guard !isBlackout(at: date) else {
            log.notice("shouldFire=false: blackout")
            return false
        }
        guard !isSkippedWeekday(at: date) else {
            log.notice("shouldFire=false: skipped weekday")
            return false
        }
        log.notice("shouldFire=true")
        return true
    }

    func isWithinActiveHours(at date: Date = Date()) -> Bool {
        // If active hours toggle is off, always return true
        guard settings.useActiveHours else {
            log.notice("isWithinActiveHours: useActiveHours=false, always active")
            return true
        }

        let hour = Calendar.current.component(.hour, from: date)
        let start = settings.activeHoursStart
        let end = settings.activeHoursEnd
        let result: Bool
        if start == end {
            result = true // same = all day
        } else if start < end {
            result = hour >= start && hour < end
        } else {
            // Overnight range (e.g. 22–6)
            result = hour >= start || hour < end
        }
        log.notice("isWithinActiveHours: hour=\(hour), start=\(start), end=\(end), result=\(result)")
        return result
    }

    func isBlackout(at date: Date = Date()) -> Bool {
        // Blackout windows will be fully implemented in Phase 4 (Settings)
        return false
    }

    private func isSkippedWeekday(at date: Date = Date()) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        let skipped = settings.skipWeekdays
        return skipped.contains(weekday)
    }
}
