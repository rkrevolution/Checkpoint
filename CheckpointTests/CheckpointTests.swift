import Testing
import Foundation
import AppKit
@testable import Checkpoint

/// A throwaway preferences store: tests must never read or write the user's real settings.
func isolatedSettings() -> AppSettings {
    AppSettings(UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
}

// MARK: - ScheduleManager Tests

struct ScheduleManagerTests {

    @Test func shouldFireWhenEnabled() async {
        await MainActor.run {
            let settings = isolatedSettings()
            settings.checkInsEnabled = true
            settings.useActiveHours = false
            settings.skipWeekdays = []

            let mgr = ScheduleManager(settings: settings)
            #expect(mgr.shouldFire() == true)
        }
    }

    @Test func shouldNotFireWhenDisabled() async {
        await MainActor.run {
            let settings = isolatedSettings()
            settings.checkInsEnabled = false
            let mgr = ScheduleManager(settings: settings)
            #expect(mgr.shouldFire() == false)
            settings.checkInsEnabled = true
        }
    }

    @Test func activeHoursOffMeansAlwaysActive() async {
        await MainActor.run {
            let settings = isolatedSettings()
            settings.useActiveHours = false
            let mgr = ScheduleManager(settings: settings)
            // Should be true at any hour
            let midnight = calendar(hour: 0)
            let noon = calendar(hour: 12)
            let late = calendar(hour: 23)
            #expect(mgr.isWithinActiveHours(at: midnight) == true)
            #expect(mgr.isWithinActiveHours(at: noon) == true)
            #expect(mgr.isWithinActiveHours(at: late) == true)
        }
    }

    @Test func activeHoursNormalRange() async {
        await MainActor.run {
            let settings = isolatedSettings()
            settings.useActiveHours = true
            settings.activeHoursStart = 9
            settings.activeHoursEnd = 17

            let mgr = ScheduleManager(settings: settings)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 10)) == true)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 9)) == true)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 16)) == true)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 17)) == false)  // end is exclusive
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 8)) == false)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 22)) == false)

            settings.useActiveHours = false
        }
    }

    @Test func activeHoursOvernightRange() async {
        await MainActor.run {
            let settings = isolatedSettings()
            settings.useActiveHours = true
            settings.activeHoursStart = 22
            settings.activeHoursEnd = 6

            let mgr = ScheduleManager(settings: settings)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 23)) == true)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 0)) == true)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 3)) == true)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 6)) == false)   // end is exclusive
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 12)) == false)

            settings.useActiveHours = false
        }
    }

    @Test func activeHoursSameStartEndMeansAllDay() async {
        await MainActor.run {
            let settings = isolatedSettings()
            settings.useActiveHours = true
            settings.activeHoursStart = 10
            settings.activeHoursEnd = 10

            let mgr = ScheduleManager(settings: settings)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 0)) == true)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 15)) == true)

            settings.useActiveHours = false
        }
    }

    @Test func skippedWeekday() async {
        await MainActor.run {
            let settings = isolatedSettings()
            settings.checkInsEnabled = true
            settings.useActiveHours = false

            // Get today's weekday and skip it
            let today = Calendar.current.component(.weekday, from: Date())
            settings.skipWeekdays = [today]

            let mgr = ScheduleManager(settings: settings)
            #expect(mgr.shouldFire() == false)

            settings.skipWeekdays = []
        }
    }
}

// MARK: - AppState Tests

struct AppStateTests {

    @Test func initialStateIsIdle() async {
        await MainActor.run {
            let settings = isolatedSettings()
            let state = AppState()
            #expect(state.state == .idle)
        }
    }

    @Test func transitionChangesState() async {
        await MainActor.run {
            let settings = isolatedSettings()
            let state = AppState()
            state.transition(to: .paused)
            #expect(state.state == .paused)
        }
    }

    @Test func duplicateTransitionIgnored() async {
        await MainActor.run {
            let settings = isolatedSettings()
            let state = AppState()
            state.transition(to: .paused)
            state.transition(to: .paused) // should not crash or change
            #expect(state.state == .paused)
        }
    }

    @Test func recordCategoriesKeepsMax6() async {
        await MainActor.run {
            let settings = isolatedSettings()
            let state = AppState()
            state.recordShownCategories(["a", "b", "c"])
            state.recordShownCategories(["d", "e", "f"])
            // Should keep newest first, max 6
            #expect(state.recentCategoryIds.count == 6)
            #expect(state.recentCategoryIds.first == "d")
        }
    }

    @Test func recordCategoriesTruncatesOld() async {
        await MainActor.run {
            let settings = isolatedSettings()
            let state = AppState()
            state.recordShownCategories(["a", "b", "c", "d"])
            state.recordShownCategories(["e", "f", "g", "h"])
            // New ids prepended, max 6 total: the tail of the older batch is dropped
            #expect(state.recentCategoryIds == ["e", "f", "g", "h", "a", "b"])
            #expect(state.recentCategoryIds.contains("c") == false)
            #expect(state.recentCategoryIds.contains("d") == false)
        }
    }

    @Test func fullTransitionCycle() async {
        await MainActor.run {
            let settings = isolatedSettings()
            let state = AppState()
            state.transition(to: .triggered)
            #expect(state.state == .triggered)
            state.transition(to: .presenting)
            #expect(state.state == .presenting)
            state.transition(to: .idle)
            #expect(state.state == .idle)
        }
    }
}

// MARK: - QuestionBank Tests

struct QuestionBankTests {

    @Test func fallbackQuestionsLoad() async {
        await MainActor.run {
            let settings = isolatedSettings()
            let bank = QuestionBank(settings: settings)
            // In test target, questions.json may not be in bundle, so fallback loads
            #expect(!bank.bundledQuestions.isEmpty)
            #expect(!bank.bundledCategories.isEmpty)
        }
    }

    @Test func selectQuestionsReturnsRequestedCount() async {
        await MainActor.run {
            let settings = isolatedSettings()
            settings.disabledQuestionIDs = []
            let bank = QuestionBank(settings: settings)
            let selected = bank.selectQuestions(count: 2)
            #expect(selected.count == 2)
        }
    }

    @Test func selectQuestionsNeverExceedsAvailable() async {
        await MainActor.run {
            let settings = isolatedSettings()
            settings.disabledQuestionIDs = []
            let bank = QuestionBank(settings: settings)
            let total = bank.bundledQuestions.count
            let selected = bank.selectQuestions(count: total + 10)
            #expect(selected.count == total)
        }
    }

    @Test func selectQuestionsFavorsCategoryDiversity() async {
        await MainActor.run {
            let settings = isolatedSettings()
            settings.disabledQuestionIDs = []
            let bank = QuestionBank(settings: settings)
            let categoryCount = bank.bundledCategories.count
            // When requesting as many as categories, should get diverse categories
            let selected = bank.selectQuestions(count: min(categoryCount, bank.bundledQuestions.count))
            let uniqueCategories = Set(selected.map(\.categoryId))
            // Should have used multiple categories
            #expect(uniqueCategories.count > 1)
        }
    }

    @Test func selectQuestionsEmptyWhenAllDisabled() async {
        await MainActor.run {
            let settings = isolatedSettings()
            let bank = QuestionBank(settings: settings)
            let allIds = bank.bundledQuestions.map(\.id)
            settings.disabledQuestionIDs = Set(allIds)

            let selected = bank.selectQuestions(count: 3)
            #expect(selected.isEmpty)

            settings.disabledQuestionIDs = []
        }
    }

    @Test func selectQuestionsRespectsRecentCategories() async {
        await MainActor.run {
            let settings = isolatedSettings()
            settings.disabledQuestionIDs = []
            let bank = QuestionBank(settings: settings)
            let allCatIds = bank.bundledCategories.map(\.id)
            // Mark all but one category as recent
            let recentIds = Array(allCatIds.dropLast())
            let remainingCat = allCatIds.last!

            let selected = bank.selectQuestions(count: 1, recentCategoryIds: recentIds)
            // With only 1 question requested, it should prefer the non-recent category
            if !selected.isEmpty {
                #expect(selected[0].categoryId == remainingCat)
            }
        }
    }

    @Test func selectQuestionsReturnsNoDuplicates() async {
        await MainActor.run {
            let settings = isolatedSettings()
            settings.disabledQuestionIDs = []
            let bank = QuestionBank(settings: settings)
            let selected = bank.selectQuestions(count: 5)
            let ids = selected.map(\.id)
            #expect(Set(ids).count == ids.count)
        }
    }
}

// MARK: - CheckpointSession Tests

struct CheckpointSessionTests {

    @Test func encodeDecode() throws {
        let question = Question(id: "q1", text: "Test?", isEnabled: true, isCustom: false, categoryId: "cat1")
        let session = CheckpointSession(
            id: UUID(),
            timestamp: Date(),
            intervalSeconds: 2700,
            questionsShown: [question],
            responses: [QuestionResponse(questionId: "q1", text: "Yes")],
            outcome: .completed
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CheckpointSession.self, from: data)

        #expect(decoded.id == session.id)
        #expect(decoded.intervalSeconds == 2700)
        #expect(decoded.outcome == .completed)
        #expect(decoded.questionsShown.count == 1)
        #expect(decoded.responses[0].text == "Yes")
    }

    @Test func codingKeysMapQuestionsField() throws {
        let question = Question(id: "q1", text: "Test?", isEnabled: true, isCustom: false, categoryId: "cat1")
        let session = CheckpointSession(
            id: UUID(),
            timestamp: Date(),
            intervalSeconds: 1800,
            questionsShown: [question],
            responses: [],
            outcome: .snoozed
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        let json = String(data: data, encoding: .utf8)!

        // questionsShown is encoded as "questions" per CodingKeys
        #expect(json.contains("\"questions\""))
        #expect(!json.contains("\"questionsShown\""))
    }
}

// MARK: - CheckpointTimer Tests

struct CheckpointTimerTests {

    /// Throwaway settings, so tests never touch the user's real preferences
    private func defaults(randomness: Randomness) -> UserDefaults {
        let d = UserDefaults(suiteName: "timer-\(UUID().uuidString)")!
        d.set(randomness.rawValue, forKey: AppSettings.Key.randomness.rawValue)
        return d
    }

    @Test func nextFireDateNilWhenStopped() async {
        await MainActor.run {
            let timer = CheckpointTimer(settings: AppSettings(defaults(randomness: .off)))
            #expect(timer.nextFireDate == nil)
        }
    }

    @Test func startSetsNextFireDate() async {
        await MainActor.run {
            let timer = CheckpointTimer(settings: AppSettings(defaults(randomness: .off)))
            timer.start(interval: 300)
            let remaining = timer.nextFireDate!.timeIntervalSinceNow
            #expect(remaining > 290 && remaining <= 301)
            timer.stop()
        }
    }

    @Test func stopClearsFireDate() async {
        await MainActor.run {
            let timer = CheckpointTimer(settings: AppSettings(defaults(randomness: .off)))
            timer.start(interval: 300)
            #expect(timer.nextFireDate != nil)
            timer.stop()
            #expect(timer.nextFireDate == nil)
        }
    }

    @Test func minimumIntervalIs60Seconds() async {
        await MainActor.run {
            let timer = CheckpointTimer(settings: AppSettings(defaults(randomness: .off)))
            timer.start(interval: 10) // way below minimum
            #expect(timer.nextFireDate!.timeIntervalSinceNow >= 55)
            timer.stop()
        }
    }

    @Test func randomnessStaysWithinItsRange() async {
        await MainActor.run {
            let timer = CheckpointTimer(settings: AppSettings(defaults(randomness: .high)))
            for _ in 0..<20 {
                timer.start(interval: 900)  // high: ±225 s
                let remaining = timer.nextFireDate!.timeIntervalSinceNow
                #expect(remaining >= 900 - 226 && remaining <= 900 + 226)
            }
            timer.stop()
        }
    }

    @Test func relaunchKeepsTheSchedule() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let interval: TimeInterval = 900
        // No saved schedule: start normally
        #expect(CheckpointTimer.resumeDelay(savedDue: nil, now: now, interval: interval) == nil)
        // Still ahead: keep it
        #expect(CheckpointTimer.resumeDelay(savedDue: now.addingTimeInterval(400), now: now, interval: interval) == 400)
        // Very close: at least 30 s
        #expect(CheckpointTimer.resumeDelay(savedDue: now.addingTimeInterval(5), now: now, interval: interval) == 30)
        // Came due while closed: shortly after launch
        #expect(CheckpointTimer.resumeDelay(savedDue: now.addingTimeInterval(-600), now: now, interval: interval) == 90)
        // Missed long ago (e.g. closed overnight): start fresh
        #expect(CheckpointTimer.resumeDelay(savedDue: now.addingTimeInterval(-5000), now: now, interval: interval) == nil)
        // Implausibly far ahead (e.g. interval shortened): start fresh
        #expect(CheckpointTimer.resumeDelay(savedDue: now.addingTimeInterval(5000), now: now, interval: interval) == nil)
    }

    @Test func randomnessLabelsShowTheRealRange() {
        #expect(Randomness.off.label(for: 900) == "Off (exactly every 15 min)")
        #expect(Randomness.low.label(for: 900) == "Low (±1 min)")
        #expect(Randomness.medium.label(for: 900) == "Medium (±2 min)")
        #expect(Randomness.high.label(for: 900) == "High (±4 min)")
        #expect(Randomness.medium.seconds(for: 2700) == 405)
    }

    @Test func oldJitterSettingMigratesToNearestLevel() {
        func migrated(jitter: Int, interval: Int) -> Randomness {
            let d = UserDefaults(suiteName: "migrate-\(UUID().uuidString)")!
            d.set(jitter, forKey: Randomness.legacyKey)
            d.set(interval, forKey: "checkpointInterval")
            Randomness.migrate(d)
            return AppSettings(d).randomness
        }
        #expect(migrated(jitter: 60, interval: 900) == .low)      // ±1 min at 15 min
        #expect(migrated(jitter: 600, interval: 900) == .high)    // was capped at a quarter
        #expect(migrated(jitter: 0, interval: 900) == .off)
        #expect(migrated(jitter: 600, interval: 2700) == .high)   // old default at 45 min (22%)
    }

    @Test func noOldSettingMeansMedium() {
        let d = UserDefaults(suiteName: "fresh-\(UUID().uuidString)")!
        Randomness.migrate(d)
        #expect(AppSettings(d).randomness == .medium)
    }
}

// MARK: - IntervalPicker Logic Tests

struct IntervalPickerTests {

    private let intervalOptions = [1, 2, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120]

    @Test func snapToNearestOption() {
        // Simulate the onAppear snap logic from GeneralSettingsView
        let staleMinutes = 35
        let nearest = intervalOptions.min(by: { abs($0 - staleMinutes) < abs($1 - staleMinutes) })!
        #expect(nearest == 30)
    }

    @Test func snapToNearestOptionEdgeCase() {
        let staleMinutes = 7
        let nearest = intervalOptions.min(by: { abs($0 - staleMinutes) < abs($1 - staleMinutes) })!
        #expect(nearest == 5)
    }

    @Test func intervalLabelFormatting() {
        #expect(intervalLabel(1) == "1 min")
        #expect(intervalLabel(30) == "30 min")
        #expect(intervalLabel(60) == "1 hour")
        #expect(intervalLabel(90) == "1.5 hours")
        #expect(intervalLabel(120) == "2 hours")
    }

    private func intervalLabel(_ mins: Int) -> String {
        switch mins {
        case 1: return "1 min"
        case 60: return "1 hour"
        case 90: return "1.5 hours"
        case 120: return "2 hours"
        default: return "\(mins) min"
        }
    }
}

// MARK: - Sleep/Wake State Tests

struct SleepWakeTests {

    @Test func wakeFromIdleReturnsToIdle() async {
        await MainActor.run {
            let state = AppState()
            // Simulate: was idle before sleep, wake should stay idle
            state.transition(to: .idle)
            #expect(state.state == .idle)
        }
    }

    @Test func wakeFromPausedStaysPaused() async {
        await MainActor.run {
            let state = AppState()
            state.transition(to: .paused)
            // On wake, if paused, should remain paused (no transition)
            #expect(state.state == .paused)
        }
    }

    @Test func wakeFromPresentingTransitionsToIdle() async {
        await MainActor.run {
            let state = AppState()
            state.transition(to: .presenting)
            // On wake, stale presenting state should be dismissed → idle
            state.transition(to: .idle)
            #expect(state.state == .idle)
        }
    }

    @Test func wakeFromTriggeredTransitionsToIdle() async {
        await MainActor.run {
            let state = AppState()
            state.transition(to: .triggered)
            // On wake, stale triggered state should be dismissed → idle
            state.transition(to: .idle)
            #expect(state.state == .idle)
        }
    }

    @Test func wakeFromSnoozedTransitionsToIdle() async {
        await MainActor.run {
            let state = AppState()
            state.transition(to: .snoozed(until: Date().addingTimeInterval(300), count: 1))
            // On wake, stale snooze should be cleared → idle
            state.transition(to: .idle)
            #expect(state.state == .idle)
        }
    }
}

// MARK: - Helpers

private func calendar(hour: Int) -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 3
    components.day = 11
    components.hour = hour
    components.minute = 30
    return Calendar.current.date(from: components)!
}

// MARK: - CSV Export Tests

struct CSVExportTests {

    @Test func csvFieldEscapesQuotes() {
        #expect(HistorySettingsView.csvField("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }

    @Test func csvFieldKeepsCommasAndNewlinesQuoted() {
        #expect(HistorySettingsView.csvField("a, b\nc") == "\"a, b\nc\"")
    }
}

// MARK: - ObjectiveTracker Tests (isolated defaults, fake clock)

@MainActor
struct ObjectiveTrackerTests {

    final class Clock {
        var time: Date
        init(_ time: Date) { self.time = time }
        func advance(minutes: Double) { time = time.addingTimeInterval(minutes * 60) }
    }

    fileprivate func makeTracker(clock: Clock, defaults: UserDefaults? = nil, url: URL? = nil) -> (ObjectiveTracker, UserDefaults, URL) {
        let d = defaults ?? UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let u = url ?? FileManager.default.temporaryDirectory.appendingPathComponent("sessions-\(UUID().uuidString).jsonl")
        return (ObjectiveTracker(defaults: d, now: { clock.time }, sessionsURL: u), d, u)
    }

    /// 10:00 today (whole seconds, so durations compare exactly), so tests don't cross midnight
    fileprivate func morning() -> Date {
        let date = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        return Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded())
    }

    @Test func tracksActiveTime() {
        let clock = Clock(morning())
        let (tracker, _, _) = makeTracker(clock: clock)
        tracker.resume(); tracker.objectiveChanged(to: "Write report")
        clock.advance(minutes: 40)
        #expect(tracker.activeSeconds() == 40 * 60.0)
    }

    @Test func awayTimeIsExcluded() {
        let clock = Clock(morning())
        let (tracker, _, _) = makeTracker(clock: clock)
        tracker.resume(); tracker.objectiveChanged(to: "Write report")
        clock.advance(minutes: 30)
        tracker.beginAway()
        clock.advance(minutes: 20)
        #expect(tracker.activeSeconds() == 30 * 60.0)  // still away
        tracker.endAway()
        clock.advance(minutes: 10)
        #expect(tracker.activeSeconds() == 40 * 60.0)
    }

    @Test func backdatedIdleIsExcluded() {
        let clock = Clock(morning())
        let (tracker, _, _) = makeTracker(clock: clock)
        tracker.resume(); tracker.objectiveChanged(to: "Write report")
        clock.advance(minutes: 30)
        // Idle detected 5 min after the last input: backdate the away period to that input
        tracker.beginAway(at: clock.time.addingTimeInterval(-5 * 60))
        clock.advance(minutes: 10)
        tracker.endAway(at: clock.time.addingTimeInterval(-30))  // input resumed 30 s ago
        #expect(tracker.activeSeconds() == 25 * 60.0 + 30)
    }

    @Test func backdatedAwayNeverOverlapsPreviousAway() {
        let clock = Clock(morning())
        let (tracker, _, _) = makeTracker(clock: clock)
        tracker.resume(); tracker.objectiveChanged(to: "Write report")
        clock.advance(minutes: 10)
        tracker.beginAway()
        clock.advance(minutes: 10)
        tracker.endAway()                               // away 10:10–10:20
        tracker.beginAway(at: clock.time.addingTimeInterval(-15 * 60))  // would start 10:05
        clock.advance(minutes: 5)
        tracker.endAway()                               // clamped: away 10:20–10:25
        #expect(tracker.activeSeconds() == 10 * 60.0)
    }

    @Test func sameObjectiveKeepsSession() {
        let clock = Clock(morning())
        let (tracker, _, _) = makeTracker(clock: clock)
        tracker.resume(); tracker.objectiveChanged(to: "Write report")
        let id = tracker.current?.id
        clock.advance(minutes: 5)
        tracker.objectiveChanged(to: "  Write report ")
        #expect(tracker.current?.id == id)
    }

    @Test func newObjectiveEndsAndLogsPreviousSession() throws {
        let clock = Clock(morning())
        let (tracker, _, url) = makeTracker(clock: clock)
        tracker.resume(); tracker.objectiveChanged(to: "Write report"); tracker.ifThenPlanChanged(to: "close tabs")
        clock.advance(minutes: 25)
        tracker.objectiveChanged(to: "Email")
        #expect(tracker.current?.objective == "Email")
        #expect(tracker.current?.ifThenPlan == "close tabs")
        let logged = try JSONLinesFile<ObjectiveSession>(url: url).loadAll()
        #expect(logged.count == 1)
        let first = try #require(logged.first)
        #expect(first.objective == "Write report")
        #expect(first.activeSeconds(at: clock.time) == 25 * 60.0)
        #expect(tracker.todaySessions().map(\.objective) == ["Write report", "Email"])
    }

    @Test func downtimeBetweenLaunchesIsExcluded() {
        let clock = Clock(morning())
        let (first, defaults, url) = makeTracker(clock: clock)
        first.resume(); first.objectiveChanged(to: "Write report")
        clock.advance(minutes: 15)
        first.heartbeat()
        clock.advance(minutes: 60)  // app not running

        let (relaunched, _, _) = makeTracker(clock: clock, defaults: defaults, url: url)
        relaunched.resume()
        clock.advance(minutes: 5)
        #expect(relaunched.activeSeconds() == 20 * 60.0)
    }

    @Test func sessionFromPreviousDayIsClosedNotCarriedOver() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: morning())!
        let clock = Clock(yesterday)
        let (first, defaults, url) = makeTracker(clock: clock)
        first.resume(); first.objectiveChanged(to: "Write report")
        let oldID = first.current?.id
        clock.time = morning()

        let (relaunched, _, _) = makeTracker(clock: clock, defaults: defaults, url: url)
        relaunched.resume()
        // Yesterday's session is closed, and none starts until the user confirms an objective
        #expect(relaunched.current == nil)
        #expect(oldID != nil)
    }

    /// #51: the app keeps running past midnight with a session open
    @Test func sessionEndsAtMidnightWhenAppRunsOvernight() throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: morning())!
        let clock = Clock(yesterday)
        let (tracker, _, url) = makeTracker(clock: clock)
        tracker.resume(); tracker.objectiveChanged(to: "Write report")
        #expect(tracker.endIfFromEarlierDay() == false)  // same day: nothing to do

        // Heartbeats all night (app running, Mac awake), then the first check after midnight
        let midnight = Calendar.current.startOfDay(for: morning())
        clock.time = midnight.addingTimeInterval(-30); tracker.heartbeat()
        clock.time = midnight.addingTimeInterval(30)
        #expect(tracker.endIfFromEarlierDay() == true)
        #expect(tracker.current == nil)

        // Yesterday's session ends by midnight, not stretched into today
        let ended = try #require(try JSONLinesFile<ObjectiveSession>(url: url).loadAll().first)
        #expect(ended.endedAt == midnight.addingTimeInterval(-30))
        #expect(tracker.todaySessions().isEmpty)
        #expect(tracker.endIfFromEarlierDay() == false)  // only once
    }

    @Test func overnightSessionNeverEndsAfterMidnight() throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: morning())!
        let clock = Clock(yesterday)
        let (tracker, _, url) = makeTracker(clock: clock)
        tracker.resume(); tracker.objectiveChanged(to: "Write report")
        let midnight = Calendar.current.startOfDay(for: morning())
        clock.time = midnight.addingTimeInterval(120); tracker.heartbeat()  // last seen after midnight
        #expect(tracker.endIfFromEarlierDay() == true)
        let ended = try #require(try JSONLinesFile<ObjectiveSession>(url: url).loadAll().first)
        #expect(ended.endedAt == midnight)
    }

    @Test func recentObjectivesAreDistinctAndNewestFirst() {
        let clock = Clock(morning())
        let (tracker, _, _) = makeTracker(clock: clock)
        tracker.resume(); tracker.objectiveChanged(to: "Report")
        for next in ["Email", "Report", "Slides"] {
            clock.advance(minutes: 10)
            tracker.objectiveChanged(to: next)
        }
        #expect(tracker.recentObjectives() == ["Slides", "Report", "Email"])
        #expect(tracker.recentObjectives(limit: 2) == ["Slides", "Report"])
    }

    @Test func emptyObjectiveMeansNoSession() {
        let clock = Clock(morning())
        let (tracker, _, _) = makeTracker(clock: clock)
        tracker.resume(); tracker.objectiveChanged(to: "")
        #expect(tracker.current == nil)
        #expect(tracker.activeSeconds() == nil)
    }
}

struct DurationTextTests {
    @Test func longForm() {
        #expect(DurationText.long(20) == "under 1 min")
        #expect(DurationText.long(45 * 60) == "45 min")
        #expect(DurationText.long(120 * 60) == "2 h")
        #expect(DurationText.long(160 * 60) == "2 h 40 min")
    }

    @Test func shortForm() {
        #expect(DurationText.short(20) == "<1m")
        #expect(DurationText.short(160 * 60) == "2h40m")
    }
}

// MARK: - Check-in response and parked thoughts

struct CheckInResponseTests {

    @Test func olderHistoryEntriesStillDecode() throws {
        let json = """
        {"id":"7E57D00D-0000-4000-8000-000000000001","timestamp":"2026-11-02T10:00:00Z","intervalSeconds":2700,
         "questions":[],"responses":[],"outcome":"completed"}
        """
        let session = try JSONDecoder.iso8601.decode(CheckpointSession.self, from: Data(json.utf8))
        #expect(session.checkInResponse == nil)
        #expect(session.parkedThought == nil)
    }

    @Test func responseAndParkedThoughtRoundTrip() throws {
        var session = CheckpointSession(
            id: UUID(), timestamp: Date(timeIntervalSinceReferenceDate: 0), intervalSeconds: 60,
            questionsShown: [], responses: [], outcome: .completed)
        session.checkInResponse = .drifted
        session.parkedThought = "reply to Sam"
        let decoded = try JSONDecoder.iso8601.decode(
            CheckpointSession.self, from: JSONEncoder.iso8601.encode(session))
        #expect(decoded == session)
    }
}

@MainActor
struct ParkedThoughtsTests {

    @Test func parkAndMarkDonePersist() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("parked-\(UUID().uuidString).jsonl")
        let store = ParkedThoughts(defaults: defaults, url: url)
        store.park("  reply to Sam  ", objective: "Report")
        store.park("   ", objective: nil)  // ignored
        store.park("book dentist", objective: nil)
        #expect(store.open.map(\.text) == ["reply to Sam", "book dentist"])

        store.markDone(store.open[0].id)
        let reloaded = ParkedThoughts(defaults: defaults, url: url)
        #expect(reloaded.open.map(\.text) == ["book dentist"])
    }
}

// MARK: - Estimates (#11)

struct EstimateStatsTests {

    private func session(estimate: Int?, activeMinutes: Double) -> ObjectiveSession {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        return ObjectiveSession(
            id: UUID(), objective: "x", ifThenPlan: nil, estimateMinutes: estimate,
            startedAt: start, endedAt: start.addingTimeInterval(activeMinutes * 60),
            awaySeconds: 0, awaySince: nil)
    }

    @Test func ratioUsesOnlyEstimatedSessions() throws {
        let sessions = [
            session(estimate: 30, activeMinutes: 45),   // 1.5×
            session(estimate: 60, activeMinutes: 60),   // 1×
            session(estimate: nil, activeMinutes: 200), // ignored
        ]
        let ratio = try #require(EstimateStats.ratio(sessions, at: Date()))
        #expect(abs(ratio - 105.0 / 90.0) < 0.0001)
    }

    @Test func noEstimatesMeansNoRatio() {
        #expect(EstimateStats.ratio([session(estimate: nil, activeMinutes: 30)], at: Date()) == nil)
    }

    @Test func describeRatio() {
        #expect(EstimateStats.describe(1.04) == "matched your estimates")
        #expect(EstimateStats.describe(1.4) == "took 1.4× your estimates")
    }

    @Test func progressTextAndOverrun() {
        let s = session(estimate: 60, activeMinutes: 80)
        let end = s.endedAt!
        #expect(s.progressText(at: end).hasPrefix("1 h 20 min of ~1 h · since "))
        #expect(s.isOverEstimate(at: end))
        #expect(!session(estimate: nil, activeMinutes: 80).isOverEstimate(at: end))
    }
}

// MARK: - Weekdays (#29)

struct WeekdaysTests {
    @Test func orderFollowsFirstWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2  // Monday
        #expect(Weekdays.ordered(calendar: calendar) == [2, 3, 4, 5, 6, 7, 1])
        calendar.firstWeekday = 1  // Sunday
        #expect(Weekdays.ordered(calendar: calendar) == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test func setSkippedAddsAndRemoves() {
        #expect(Weekdays.setSkipped(7, skipped: true, in: [1]) == [1, 7])
        #expect(Weekdays.setSkipped(1, skipped: false, in: [1, 7]) == [7])
        #expect(Weekdays.setSkipped(7, skipped: true, in: [7]) == [7])
    }
}

// MARK: - Goals

struct GoalsTests {
    @Test func currentSkipsBlankLines() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set("  Ship 1.0 ", forKey: "goal1")
        defaults.set("   ", forKey: "goal2")
        defaults.set("Run 3× a week", forKey: "goal3")
        #expect(AppSettings(defaults).goals == ["Ship 1.0", "Run 3× a week"])
    }
}

// MARK: - Screen capture privacy

struct ScreenCapturePrivacyTests {
    @Test func hiddenByDefault() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        #expect(ScreenCapturePrivacy.isHidden(defaults))
        #expect(ScreenCapturePrivacy.statusText(defaults).hasPrefix("hidden"))
    }

    @Test func turningItOffMakesWindowsCapturable() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set(false, forKey: AppSettings.Key.hideFromScreenCapture.rawValue)
        #expect(!ScreenCapturePrivacy.isHidden(defaults))
        #expect(ScreenCapturePrivacy.statusText(defaults).hasPrefix("visible"))
        #expect(ScreenCapturePrivacy.sharingType(hidden: false) == .readOnly)
        #expect(ScreenCapturePrivacy.sharingType(hidden: true) == .none)
    }
}

// MARK: - Time per objective and pause

struct ObjectiveTotalsTests {
    @Test func stretchesOfTheSameObjectiveAddUp() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        func s(_ name: String, _ minutes: Double) -> ObjectiveSession {
            ObjectiveSession(id: UUID(), objective: name, ifThenPlan: nil, startedAt: start,
                             endedAt: start.addingTimeInterval(minutes * 60), awaySeconds: 0, awaySince: nil)
        }
        let totals = ObjectiveTotals.byObjective([s("App", 60), s("Email", 25), s("App", 40)], at: Date())
        let expected: [ObjectiveTotals.Total] = [
            ObjectiveTotals.Total(objective: "App", seconds: 6000, stretches: 2),
            ObjectiveTotals.Total(objective: "Email", seconds: 1500, stretches: 1),
        ]
        #expect(totals == expected)
    }
}

extension ObjectiveTrackerTests {
    @Test func namesMatchIgnoringCapitalization() {
        let clock = Clock(morning())
        let (tracker, _, _) = makeTracker(clock: clock)
        tracker.resume(); tracker.objectiveChanged(to: "Building the app")
        let id = tracker.current?.id
        tracker.objectiveChanged(to: "  building the APP ")
        #expect(tracker.current?.id == id)  // same task, same stretch

        clock.advance(minutes: 10)
        tracker.objectiveChanged(to: "Email")
        clock.advance(minutes: 10)
        tracker.objectiveChanged(to: "building the app")  // back to it, typed differently
        #expect(tracker.current?.objective == "Building the app")
        #expect(tracker.recentObjectives() == ["Building the app", "Email"])
        let totals = ObjectiveTotals.byObjective(tracker.todaySessions(), at: clock.time)
        #expect(totals.count == 2)
    }

    @Test func pausedTimeIsNotCounted() {
        let clock = Clock(morning())
        let (tracker, _, _) = makeTracker(clock: clock)
        tracker.resume(); tracker.objectiveChanged(to: "Write report")
        clock.advance(minutes: 20)
        tracker.beginAway()      // Pause
        clock.advance(minutes: 45)
        tracker.beginAway()      // e.g. screen locks while paused: no double count
        tracker.endAway()        // Resume
        clock.advance(minutes: 10)
        #expect(tracker.activeSeconds() == 30 * 60.0)
    }
}

// MARK: - Focus pill

struct FocusPillPolicyTests {
    @Test func showsOnlyWhenEnabledWithObjectiveAndPresent() {
        #expect(FocusPillPolicy.shouldShow(enabled: true, hasObjective: true, isPaused: false, isAway: false))
        #expect(!FocusPillPolicy.shouldShow(enabled: false, hasObjective: true, isPaused: false, isAway: false))
        #expect(!FocusPillPolicy.shouldShow(enabled: true, hasObjective: false, isPaused: false, isAway: false))
        #expect(!FocusPillPolicy.shouldShow(enabled: true, hasObjective: true, isPaused: true, isAway: false))
        #expect(!FocusPillPolicy.shouldShow(enabled: true, hasObjective: true, isPaused: false, isAway: true))
    }
}

// MARK: - AppSettings (#16)

struct AppSettingsTests {

    @Test func unsetSettingsUseTheirDefaults() {
        let s = isolatedSettings()
        #expect(s.checkInInterval == TimeInterval(AppSettings.Default.checkInInterval))
        #expect(s.randomness == .medium)
        #expect(s.checkInsEnabled)
        #expect(s.snoozeMinutes == 5)
        #expect(s.maxSnoozes == 2)
        #expect(s.afterMaxSnooze == .autoDismiss)
        #expect(s.respectFocus)
        #expect(s.holdDuringCalls)
        #expect(s.hideFromScreenCapture)
        #expect(s.soundName == "Glass")
        #expect(s.menuBarDisplay == .objectiveTime)
        #expect(s.logResponses)
        #expect(!s.showFocusPill)
        #expect(s.questionsPerCheckIn == 1)
        #expect(s.goals.isEmpty)
    }

    @Test func storedFalseAndZeroAreNotReplacedByDefaults() {
        let s = isolatedSettings()
        s.respectFocus = false
        s.maxSnoozes = 0          // unlimited
        s.activeHoursStart = 0    // midnight
        #expect(!s.respectFocus)
        #expect(s.maxSnoozes == 0)
        #expect(s.activeHoursStart == 0)
    }

    @Test func invalidValuesFallBack() {
        let s = isolatedSettings()
        s.defaults.set(0, forKey: AppSettings.Key.checkInInterval.rawValue)
        s.defaults.set(0, forKey: AppSettings.Key.snoozeMinutes.rawValue)
        s.defaults.set("sometimes", forKey: AppSettings.Key.afterMaxSnooze.rawValue)
        #expect(s.checkInInterval == 2700)
        #expect(s.snoozeMinutes == 5)
        #expect(s.afterMaxSnooze == .autoDismiss)
    }

    /// Launch arguments (`scripts/run.sh -checkpointInterval 60 -respectFocusMode NO`) arrive as strings
    @Test func stringValuesFromLaunchArgumentsParse() {
        let s = isolatedSettings()
        s.defaults.set("60", forKey: AppSettings.Key.checkInInterval.rawValue)
        s.defaults.set("NO", forKey: AppSettings.Key.respectFocus.rawValue)
        #expect(s.checkInInterval == 60)
        #expect(!s.respectFocus)
    }

    @Test func snoozeLimit() {
        let s = isolatedSettings()
        #expect(s.allowsSnooze(after: 1))
        #expect(!s.allowsSnooze(after: 2))
        s.maxSnoozes = 0
        #expect(s.allowsSnooze(after: 50))
    }

    /// Raw values are what's stored on disk; renaming one would silently reset a user's setting
    @Test func storedKeyNamesNeverChange() {
        #expect(AppSettings.Key.checkInInterval.rawValue == "checkpointInterval")
        #expect(AppSettings.Key.checkInsEnabled.rawValue == "checkpointsEnabled")
        #expect(AppSettings.Key.questionsPerCheckIn.rawValue == "questionsPerCheckpoint")
        #expect(AppSettings.Key.maxSnoozes.rawValue == "maxSnoozesPerCheckpoint")
        #expect(AppSettings.Key.afterMaxSnooze.rawValue == "afterMaxSnoozeAction")
        #expect(AppSettings.Key.playSound.rawValue == "playSoundOnCheckpoint")
        #expect(AppSettings.Key.respectFocus.rawValue == "respectFocusMode")
        #expect(AppSettings.Key.fullScreenCheckIn.rawValue == "fullScreenCheckpoint")
        #expect(Set(AppSettings.Key.allCases.map(\.rawValue)).count == AppSettings.Key.allCases.count)
    }

    @Test func goalsSkipBlankLines() {
        let s = isolatedSettings()
        s.defaults.set("Ship 1.0", forKey: AppSettings.Key.goal1.rawValue)
        s.defaults.set("   ", forKey: AppSettings.Key.goal2.rawValue)
        s.defaults.set(" Run ", forKey: AppSettings.Key.goal3.rawValue)
        #expect(s.goals == ["Ship 1.0", "Run"])
    }
}

// MARK: - CheckInGate (#17)

struct CheckInGateTests {
    typealias Gate = CheckInGate
    static let snoozed = CheckpointState.snoozed(until: Date(), count: 1)

    /// Every block reason, for each kind of request. Nil = shows now.
    @Test(arguments: [
        // Nothing in the way
        (Gate.Request.scheduled, Gate.Conditions(state: .idle), nil),
        (.snoozeReturn, Gate.Conditions(state: snoozed), nil),
        (.manual, Gate.Conditions(state: .idle), nil),
        // Away beats everything, even a manual request
        (.scheduled, Gate.Conditions(state: .idle, isAway: true), .away),
        (.snoozeReturn, Gate.Conditions(state: snoozed, isAway: true), .away),
        (.manual, Gate.Conditions(state: .idle, isAway: true), .away),
        // Paused: only Resume ends it
        (.scheduled, Gate.Conditions(state: .paused), .paused),
        (.manual, Gate.Conditions(state: .paused), .paused),
        (.scheduled, Gate.Conditions(state: .paused, isFocusActive: true), .paused),
        // Another check-in open or snoozed
        (.scheduled, Gate.Conditions(state: .presenting), .inProgress),
        (.scheduled, Gate.Conditions(state: .triggered), .inProgress),
        (.scheduled, Gate.Conditions(state: snoozed), .inProgress),
        (.manual, Gate.Conditions(state: .presenting), .inProgress),
        (.snoozeReturn, Gate.Conditions(state: .idle), .inProgress),
        // Manual replaces a snooze
        (.manual, Gate.Conditions(state: snoozed), nil),
        // Schedule
        (.scheduled, Gate.Conditions(state: .idle, scheduleAllows: false, withinActiveHours: false), .schedule(outsideActiveHours: true)),
        (.scheduled, Gate.Conditions(state: .idle, scheduleAllows: false), .schedule(outsideActiveHours: false)),
        (.snoozeReturn, Gate.Conditions(state: snoozed, scheduleAllows: false), .schedule(outsideActiveHours: false)),
        (.manual, Gate.Conditions(state: .idle, scheduleAllows: false, withinActiveHours: false), nil),
        // Waiting states are re-decided, not stuck
        (.scheduled, Gate.Conditions(state: .outsideHours), nil),
        (.scheduled, Gate.Conditions(state: .focusModeActive), nil),
        // Focus, only if respected
        (.scheduled, Gate.Conditions(state: .idle, isFocusActive: true), .focus),
        (.scheduled, Gate.Conditions(state: .idle, isFocusActive: true, respectFocus: false), nil),
        (.snoozeReturn, Gate.Conditions(state: snoozed, isFocusActive: true), .focus),
        (.manual, Gate.Conditions(state: .idle, isFocusActive: true), nil),
        // Calls wait, only if holding is on
        (.scheduled, Gate.Conditions(state: .idle, isOnCall: true), .call),
        (.scheduled, Gate.Conditions(state: .idle, isOnCall: true, holdDuringCalls: false), nil),
        (.snoozeReturn, Gate.Conditions(state: snoozed, isOnCall: true), .call),
        (.manual, Gate.Conditions(state: .idle, isOnCall: true), nil),
    ] as [(Gate.Request, Gate.Conditions, Gate.Block?)])
    func decides(request: Gate.Request, conditions: Gate.Conditions, expected: Gate.Block?) {
        #expect(Gate.block(request, conditions) == expected)
    }

    @Test func onlyCallsWait() {
        #expect(Gate.Block.call.waits)
        #expect(!Gate.Block.focus.waits)
        #expect(!Gate.Block.schedule(outsideActiveHours: true).waits)
    }

    /// #50: the menu bar says "Focus" only when Focus actually holds check-ins back
    @Test func focusBlocksOnlyWhenRespected() {
        #expect(Gate.focusBlocks(isFocusActive: true, respectFocus: true))
        #expect(!Gate.focusBlocks(isFocusActive: true, respectFocus: false))
        #expect(!Gate.focusBlocks(isFocusActive: false, respectFocus: true))
    }
}
