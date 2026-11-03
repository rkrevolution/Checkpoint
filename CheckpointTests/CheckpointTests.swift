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
        #expect(Goals.current(defaults) == ["Ship 1.0", "Run 3× a week"])
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
