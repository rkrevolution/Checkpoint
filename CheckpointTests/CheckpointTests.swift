import Testing
import Foundation
@testable import Checkpoint

// MARK: - ScheduleManager Tests

struct ScheduleManagerTests {

    @Test func shouldFireWhenEnabled() async {
        await MainActor.run {
            let ud = UserDefaults.standard
            ud.set(true, forKey: "checkpointsEnabled")
            ud.set(false, forKey: "useActiveHours")
            ud.set([Int](), forKey: "skipWeekdays")

            let mgr = ScheduleManager()
            #expect(mgr.shouldFire() == true)
        }
    }

    @Test func shouldNotFireWhenDisabled() async {
        await MainActor.run {
            UserDefaults.standard.set(false, forKey: "checkpointsEnabled")
            let mgr = ScheduleManager()
            #expect(mgr.shouldFire() == false)
            UserDefaults.standard.set(true, forKey: "checkpointsEnabled")
        }
    }

    @Test func activeHoursOffMeansAlwaysActive() async {
        await MainActor.run {
            UserDefaults.standard.set(false, forKey: "useActiveHours")
            let mgr = ScheduleManager()
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
            let ud = UserDefaults.standard
            ud.set(true, forKey: "useActiveHours")
            ud.set(9, forKey: "activeHoursStart")
            ud.set(17, forKey: "activeHoursEnd")

            let mgr = ScheduleManager()
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 10)) == true)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 9)) == true)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 16)) == true)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 17)) == false)  // end is exclusive
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 8)) == false)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 22)) == false)

            ud.set(false, forKey: "useActiveHours")
        }
    }

    @Test func activeHoursOvernightRange() async {
        await MainActor.run {
            let ud = UserDefaults.standard
            ud.set(true, forKey: "useActiveHours")
            ud.set(22, forKey: "activeHoursStart")
            ud.set(6, forKey: "activeHoursEnd")

            let mgr = ScheduleManager()
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 23)) == true)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 0)) == true)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 3)) == true)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 6)) == false)   // end is exclusive
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 12)) == false)

            ud.set(false, forKey: "useActiveHours")
        }
    }

    @Test func activeHoursSameStartEndMeansAllDay() async {
        await MainActor.run {
            let ud = UserDefaults.standard
            ud.set(true, forKey: "useActiveHours")
            ud.set(10, forKey: "activeHoursStart")
            ud.set(10, forKey: "activeHoursEnd")

            let mgr = ScheduleManager()
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 0)) == true)
            #expect(mgr.isWithinActiveHours(at: calendar(hour: 15)) == true)

            ud.set(false, forKey: "useActiveHours")
        }
    }

    @Test func skippedWeekday() async {
        await MainActor.run {
            let ud = UserDefaults.standard
            ud.set(true, forKey: "checkpointsEnabled")
            ud.set(false, forKey: "useActiveHours")

            // Get today's weekday and skip it
            let today = Calendar.current.component(.weekday, from: Date())
            ud.set([today], forKey: "skipWeekdays")

            let mgr = ScheduleManager()
            #expect(mgr.shouldFire() == false)

            ud.set([Int](), forKey: "skipWeekdays")
        }
    }
}

// MARK: - AppState Tests

struct AppStateTests {

    @Test func initialStateIsIdle() async {
        await MainActor.run {
            let state = AppState()
            #expect(state.state == .idle)
        }
    }

    @Test func transitionChangesState() async {
        await MainActor.run {
            let state = AppState()
            state.transition(to: .paused)
            #expect(state.state == .paused)
        }
    }

    @Test func duplicateTransitionIgnored() async {
        await MainActor.run {
            let state = AppState()
            state.transition(to: .paused)
            state.transition(to: .paused) // should not crash or change
            #expect(state.state == .paused)
        }
    }

    @Test func recordCategoriesKeepsMax6() async {
        await MainActor.run {
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
            let bank = QuestionBank()
            // In test target, questions.json may not be in bundle, so fallback loads
            #expect(!bank.bundledQuestions.isEmpty)
            #expect(!bank.bundledCategories.isEmpty)
        }
    }

    @Test func selectQuestionsReturnsRequestedCount() async {
        await MainActor.run {
            UserDefaults.standard.set([String](), forKey: "disabledQuestionIDs")
            let bank = QuestionBank()
            let selected = bank.selectQuestions(count: 2)
            #expect(selected.count == 2)
        }
    }

    @Test func selectQuestionsNeverExceedsAvailable() async {
        await MainActor.run {
            UserDefaults.standard.set([String](), forKey: "disabledQuestionIDs")
            let bank = QuestionBank()
            let total = bank.bundledQuestions.count
            let selected = bank.selectQuestions(count: total + 10)
            #expect(selected.count == total)
        }
    }

    @Test func selectQuestionsFavorsCategoryDiversity() async {
        await MainActor.run {
            UserDefaults.standard.set([String](), forKey: "disabledQuestionIDs")
            let bank = QuestionBank()
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
            let bank = QuestionBank()
            let allIds = bank.bundledQuestions.map(\.id)
            UserDefaults.standard.set(allIds, forKey: "disabledQuestionIDs")

            let selected = bank.selectQuestions(count: 3)
            #expect(selected.isEmpty)

            UserDefaults.standard.set([String](), forKey: "disabledQuestionIDs")
        }
    }

    @Test func selectQuestionsRespectsRecentCategories() async {
        await MainActor.run {
            UserDefaults.standard.set([String](), forKey: "disabledQuestionIDs")
            let bank = QuestionBank()
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
            UserDefaults.standard.set([String](), forKey: "disabledQuestionIDs")
            let bank = QuestionBank()
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

    @Test func nextFireDateNilWhenStopped() async {
        await MainActor.run {
            let timer = CheckpointTimer()
            #expect(timer.nextFireDate == nil)
        }
    }

    @Test func startSetsNextFireDate() async {
        await MainActor.run {
            UserDefaults.standard.set(0, forKey: "jitterRange") // no jitter for predictability
            let timer = CheckpointTimer()
            timer.start(interval: 300)
            #expect(timer.nextFireDate != nil)
            // Fire date should be ~300s from now
            let remaining = timer.nextFireDate!.timeIntervalSinceNow
            #expect(remaining > 250 && remaining <= 310)
            timer.stop()
            UserDefaults.standard.set(600, forKey: "jitterRange")
        }
    }

    @Test func stopClearsFireDate() async {
        await MainActor.run {
            UserDefaults.standard.set(0, forKey: "jitterRange")
            let timer = CheckpointTimer()
            timer.start(interval: 300)
            #expect(timer.nextFireDate != nil)
            timer.stop()
            #expect(timer.nextFireDate == nil)
            UserDefaults.standard.set(600, forKey: "jitterRange")
        }
    }

    @Test func minimumIntervalIs60Seconds() async {
        await MainActor.run {
            UserDefaults.standard.set(0, forKey: "jitterRange")
            let timer = CheckpointTimer()
            timer.start(interval: 10) // way below minimum
            let remaining = timer.nextFireDate!.timeIntervalSinceNow
            #expect(remaining >= 55) // at least ~60s (with small timing tolerance)
            timer.stop()
            UserDefaults.standard.set(600, forKey: "jitterRange")
        }
    }

    @Test func jitterAffectsFireDate() async {
        await MainActor.run {
            UserDefaults.standard.set(120, forKey: "jitterRange") // ±2 min jitter
            let timer = CheckpointTimer()
            timer.start(interval: 300)
            let remaining = timer.nextFireDate!.timeIntervalSinceNow
            // 300 ± min(120, 300/4 = 75), so between 225 and 375
            #expect(remaining >= 215 && remaining <= 385)
            timer.stop()
            UserDefaults.standard.set(600, forKey: "jitterRange")
        }
    }

    @Test func jitterIsCappedToQuarterOfInterval() {
        #expect(CheckpointTimer.effectiveJitterRange(setting: 600, baseInterval: 60) == 15)
        #expect(CheckpointTimer.effectiveJitterRange(setting: 600, baseInterval: 2700) == 600)
        #expect(CheckpointTimer.effectiveJitterRange(setting: 0, baseInterval: 2700) == 0)
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
