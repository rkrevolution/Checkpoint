import AppKit
import Combine
import os.log

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "CheckInScheduler")

/// When check-ins happen (#18): the interval timer, snoozes, check-ins held for a call, the day's
/// count, pause and resume, and noticing when check-ins have stalled.
///
/// Every path asks `CheckInGate` before showing anything. The scheduler decides *when*; showing
/// the card is the window router's job (`onPresent`), and the card reports back through
/// `answered(_:)` and `snoozed(_:snoozeCount:)`.
@MainActor
final class CheckInScheduler {

    /// Show this check-in now. `allowSnooze` is false once "Not now" has been used up.
    var onPresent: ((_ session: CheckpointSession, _ snoozeCount: Int, _ allowSnooze: Bool) -> Void)?
    /// Active hours just ended after at least one check-in today.
    var onEndOfActiveHours: (() -> Void)?
    /// Close any open card (pause, away, restart).
    var onDismissCard: (() -> Void)?

    /// A check-in came due during a call; it shows (quietly) when the call ends (#1).
    private(set) var checkInHeldForCall = false
    private(set) var day = DayCount()

    private let appState: AppState
    private let settings: AppSettings
    private let scheduleManager: ScheduleManager
    private let questionBank: QuestionBank
    private let responseLog: ResponseLog
    private let presence: PresenceMonitor
    /// Where the next due time is remembered across relaunches.
    private let store: UserDefaults

    private var timer: CheckpointTimer?
    private var snoozeTimer: DispatchSourceTimer?
    /// Start of the stretch the card reports as elapsed. Reset when the timer (re)starts, on
    /// return from away, when a check-in is answered, and after off hours (nil: use the interval).
    private var elapsedSince: Date?
    private var cancellables = Set<AnyCancellable>()

    private static let nextCheckInDueKey = "nextCheckInDue"

    init(appState: AppState, settings: AppSettings, scheduleManager: ScheduleManager,
         questionBank: QuestionBank, responseLog: ResponseLog, presence: PresenceMonitor,
         store: UserDefaults) {
        self.appState = appState
        self.settings = settings
        self.scheduleManager = scheduleManager
        self.questionBank = questionBank
        self.responseLog = responseLog
        self.presence = presence
        self.store = store
    }

    // MARK: - Timer

    var isStarted: Bool { timer != nil }
    var nextFireDate: Date? { timer?.nextFireDate }

    /// Starts the interval timer, keeping a check-in that was due before a relaunch.
    func start() {
        let interval = settings.checkInInterval
        log.notice("━━━ TIMER STARTING ━━━")
        log.notice("  Base interval: \(Int(interval))s (\(Int(interval)/60)min)")
        log.notice("  Randomness: \(self.settings.randomness.label(for: interval), privacy: .public)")
        log.notice("  Active hours: \(self.settings.useActiveHours ? "on" : "off (always active)")")
        let timer = CheckpointTimer(settings: settings)
        timer.onFire = { [weak self] in self?.timerFired() }
        timer.onSchedule = { [store] due in store.set(due, forKey: Self.nextCheckInDueKey) }
        let resume = CheckpointTimer.resumeDelay(
            savedDue: store.object(forKey: Self.nextCheckInDueKey) as? Date, now: Date(), interval: interval)
        if let resume { log.notice("  Keeping the schedule from before the relaunch: first check-in in \(Int(resume))s") }
        timer.start(interval: interval, firstFireIn: resume)
        self.timer = timer
        elapsedSince = Date()
        observeIntervalSetting()
    }

    /// A fresh interval from now; the card's elapsed time starts again too.
    private func restartInterval() {
        timer?.restart(interval: settings.checkInInterval)
        elapsedSince = Date()
    }

    /// A check-in just ended (answered or dropped). The next one is a full interval from now,
    /// so time spent snoozed, held for a call or with the card open doesn't shorten the gap (#52).
    private func startNextInterval(after reason: String) {
        log.notice("Check-in ended (\(reason, privacy: .public)): next interval starts now")
        timer?.restart(interval: settings.checkInInterval)
    }

    private func cancelSnooze() {
        snoozeTimer?.cancel()
        snoozeTimer = nil
    }

    private func observeIntervalSetting() {
        guard cancellables.isEmpty else { return }
        settings.defaults.publisher(for: \.checkpointInterval)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newInterval in
                guard let self, newInterval > 0 else { return }
                self.timer?.restart(interval: TimeInterval(newInterval))
            }
            .store(in: &cancellables)
    }

    // MARK: - Scheduled check-ins

    /// The interval timer fired, or a check-in held for a call is being delivered (`afterCall`,
    /// shown without sound).
    func timerFired(afterCall: Bool = false) {
        log.notice("handleTimerFire: currentState=\(String(describing: self.appState.state))")
        day.resetIfNewDay(now: Date())

        let block = CheckInGate.block(.scheduled, gateConditions())
        log.notice("Gate: \(block.map { "\($0)" } ?? "show", privacy: .public)")
        switch block {
        case nil:
            settle(to: .idle)
            fire(playSound: !afterCall)
        case .away:
            log.notice("User away (\(self.presence.awayReasons.map(\.rawValue), privacy: .public)), skipping")
        case .paused, .inProgress:
            log.notice("Not idle, skipping. state=\(String(describing: self.appState.state))")
        case .schedule(let outsideActiveHours):
            if outsideActiveHours {
                if day.endOfActiveHoursIsDue() { onEndOfActiveHours?() }
                settle(to: .outsideHours)
            } else {
                settle(to: .idle)
            }
        case .focus:
            settle(to: .focusModeActive)
        case .call:
            log.notice("Check-in held: on a call")
            settle(to: .idle)
            checkInHeldForCall = true
        }
    }

    /// Manual check-in: an explicit request, so the gate skips the schedule, Focus and call checks.
    func checkInNow() {
        switch CheckInGate.block(.manual, gateConditions()) {
        case nil:
            break
        case .away:
            log.notice("Manual check-in ignored: user away")
            return
        default:
            log.notice("Manual check-in ignored: state=\(String(describing: self.appState.state), privacy: .public)")
            return
        }
        log.notice("Manual check-in")
        cancelSnooze()
        day.resetIfNewDay(now: Date())
        appState.transition(to: .idle)
        fire()
    }

    /// The held check-in shows now, quietly, if the gate still allows it.
    func callChanged(inCall: Bool) {
        guard !inCall, checkInHeldForCall else { return }
        checkInHeldForCall = false
        log.notice("Call ended: showing the held check-in")
        timerFired(afterCall: true)
    }

    /// Focus only moves the state when it actually holds check-ins back, so the menu bar never
    /// says "Focus" while they keep coming (#50). Never overrides a pause, snooze or open card.
    func focusChanged(isActive: Bool) {
        let blocks = CheckInGate.focusBlocks(isFocusActive: isActive, respectFocus: settings.respectFocus)
        if blocks, appState.state == .idle {
            appState.transition(to: .focusModeActive)
        } else if !blocks, appState.state == .focusModeActive {
            appState.transition(to: .idle)
        }
    }

    /// A new day while running: the count starts again.
    func newDay() {
        day.resetIfNewDay(now: Date())
    }

    private func gateConditions() -> CheckInGate.Conditions {
        CheckInGate.Conditions(
            state: appState.state,
            isAway: presence.isAway,
            scheduleAllows: scheduleManager.shouldFire(),
            withinActiveHours: scheduleManager.isWithinActiveHours(),
            isFocusActive: presence.isFocusActive,
            respectFocus: settings.respectFocus,
            isOnCall: presence.isOnCall,
            holdDuringCalls: settings.holdDuringCalls
        )
    }

    /// Moves between the waiting states (idle, outside hours, Focus). Coming back from outside
    /// active hours starts a new stretch: the off-hours gap isn't reported as elapsed time.
    private func settle(to waiting: CheckpointState) {
        if appState.state == .outsideHours, waiting != .outsideHours {
            log.notice("Recovering from outsideHours")
            day.activeHoursStarted()
            elapsedSince = nil
        }
        appState.transition(to: waiting)
    }

    /// Builds a check-in and shows it. Callers ask `CheckInGate` first.
    private func fire(playSound: Bool = true) {
        log.notice("━━━ CHECKPOINT FIRING ━━━")
        log.notice("  Time: \(Self.clockTime(Date()))")
        appState.transition(to: .triggered)

        let questions = questionBank.selectQuestions(
            count: settings.questionsPerCheckIn, recentCategoryIds: appState.recentCategoryIds)
        appState.recordShownCategories(questions.map(\.categoryId))
        day.recordCheckIn(at: Date())

        if playSound, settings.playSound {
            NSSound(named: NSSound.Name(settings.soundName))?.play()
        }
        log.notice("Presenting checkpoint: \(questions.count) questions")
        present(CheckpointSession(questions: questions), snoozeCount: 0)
    }

    private func present(_ session: CheckpointSession, snoozeCount: Int) {
        log.notice("presentCheckpoint: snoozeCount=\(snoozeCount)")
        guard !presence.isAway else {
            log.notice("User away, not presenting")
            appState.transition(to: .idle)
            return
        }
        appState.transition(to: .presenting)
        // The current time and real elapsed time, also when it comes back after a snooze
        let now = Date()
        let elapsed = elapsedSince.map { Int(now.timeIntervalSince($0)) } ?? Int(settings.checkInInterval)
        onPresent?(session.shown(at: now, elapsed: elapsed), snoozeCount, settings.allowsSnooze(after: snoozeCount))
    }

    // MARK: - Answers from the card

    func answered(_ completed: CheckpointSession) {
        log.notice("━━━ CHECKPOINT COMPLETED ━━━")
        log.notice("  Response: \(completed.checkInResponse?.rawValue ?? "none", privacy: .public) at \(Self.clockTime(Date()))")
        elapsedSince = Date()
        record(completed)
        appState.transition(to: .idle)
        startNextInterval(after: "answered")
    }

    func snoozed(_ session: CheckpointSession, snoozeCount: Int) {
        log.notice("━━━ CHECKPOINT SNOOZED ━━━")
        log.notice("  User tapped 'Not now' at \(Self.clockTime(Date()))")
        log.notice("  Snooze #\(snoozeCount + 1), will re-present in \(self.settings.snoozeMinutes)min")
        let newCount = snoozeCount + 1
        record(session.snoozedEntry(at: Date()))

        // Out of snoozes: drop it, or ("forceModal") bring it back once more without "Not now"
        if !settings.allowsSnooze(after: newCount), settings.afterMaxSnooze == .autoDismiss {
            appState.transition(to: .idle)
            startNextInterval(after: "snooze limit reached")
            return
        }

        let seconds = settings.snoozeMinutes * 60
        appState.transition(to: .snoozed(until: Date().addingTimeInterval(TimeInterval(seconds)), count: newCount))
        cancelSnooze()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + .seconds(seconds))
        source.setEventHandler { [weak self] in
            self?.snoozeEnded(session, snoozeCount: newCount)
        }
        source.resume()
        snoozeTimer = source
    }

    private func snoozeEnded(_ session: CheckpointSession, snoozeCount: Int) {
        snoozeTimer = nil
        switch CheckInGate.block(.snoozeReturn, gateConditions()) {
        case nil:
            present(session, snoozeCount: snoozeCount)
        case .call:
            log.notice("Snoozed check-in held: on a call")
            appState.transition(to: .idle)
            checkInHeldForCall = true
        case .schedule, .focus:
            log.notice("Snoozed checkpoint dropped: schedule or Focus no longer allows it")
            appState.transition(to: .idle)
            startNextInterval(after: "snoozed check-in dropped")
        case .away, .paused, .inProgress:
            break  // cancelled or replaced in the meantime
        }
    }

    /// Saves a check-in to History, if the user keeps one.
    private func record(_ session: CheckpointSession) {
        guard settings.logResponses else { return }
        do {
            try responseLog.append(session)
        } catch {
            log.error("Couldn't save the check-in to History: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Pause, away, restart

    /// Pausing stops check-ins; any open card closes (#49).
    func pause() {
        onDismissCard?()
        timer?.stop()
        cancelSnooze()
        appState.transition(to: .paused)
    }

    func resume() {
        restartInterval()
        appState.transition(to: .idle)
    }

    /// Nothing fires or sits over the lock screen while away.
    func awayBegan() {
        checkInHeldForCall = false
        timer?.stop()
        cancelSnooze()
        onDismissCard?()
        if appState.state != .paused {
            appState.transition(to: .idle)
        }
    }

    /// Back: a fresh interval, unless the user had paused.
    func awayEnded() {
        if appState.state == .paused {
            log.notice("  User was paused before going away, staying paused")
            return
        }
        appState.transition(to: .idle)
        restartInterval()
        log.notice("  Timer restarted with interval \(Int(self.settings.checkInInterval))s")
    }

    /// Menu action shown with the stall warning: clears whatever is stuck and starts fresh.
    func restart() {
        log.notice("Restarting check-ins")
        onDismissCard?()
        cancelSnooze()
        appState.transition(to: .idle)
        if timer == nil {
            start()
        } else {
            restartInterval()
        }
    }

    // MARK: - Status

    /// Why check-ins have stopped when they shouldn't have, or nil if all is well.
    func stallReason(isCardVisible: Bool) -> String? {
        guard !presence.isAway else { return nil }
        return Self.stallReason(state: appState.state, nextFireDate: nextFireDate,
                                isCardVisible: isCardVisible, now: Date())
    }

    /// A time-blind user won't notice missing check-ins, so the menu bar shows this.
    nonisolated static func stallReason(state: CheckpointState, nextFireDate: Date?,
                                        isCardVisible: Bool, now: Date) -> String? {
        let grace: TimeInterval = 90
        switch state {
        case .idle:
            guard let next = nextFireDate else { return "the timer isn't running" }
            if next < now.addingTimeInterval(-grace) { return "a check-in is overdue" }
        case .snoozed(let until, _):
            if until < now.addingTimeInterval(-grace) { return "a snoozed check-in didn't come back" }
        case .presenting:
            if !isCardVisible { return "the check-in card isn't on screen" }
        default:
            break
        }
        return nil
    }

    /// When the next check-in will appear, or why none is scheduled. For Diagnostics and the
    /// Debug menu only: showing it in everyday UI would let users brace for check-ins.
    var nextCheckInDescription: String {
        if presence.isAway { return "none while away" }
        switch appState.state {
        case .paused: return "none while paused"
        case .presenting, .triggered: return "a check-in is showing now"
        case .snoozed(let until, _): return "snoozed until \(until.formatted(date: .omitted, time: .standard))"
        default: break
        }
        guard let next = nextFireDate else { return "timer not running" }
        let mins = max(0, Int(next.timeIntervalSinceNow / 60))
        var text = "\(next.formatted(date: .omitted, time: .standard)) (in about \(mins) min)"
        if checkInHeldForCall { text += ", one held until the call ends" }
        return text
    }

    private nonisolated static func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
}

/// Today's check-ins: how many, the last one, and whether the end-of-active-hours summary has
/// shown. Starts again on a new day.
nonisolated struct DayCount: Equatable {
    private(set) var count = 0
    private(set) var lastCheckIn: Date?
    private var summaryShown = false

    mutating func recordCheckIn(at time: Date) {
        count += 1
        lastCheckIn = time
    }

    mutating func resetIfNewDay(now: Date, calendar: Calendar = .current) {
        guard let last = lastCheckIn, !calendar.isDate(last, inSameDayAs: now) else { return }
        count = 0
        summaryShown = false
    }

    /// True once per stretch of active hours, and only after a check-in today.
    mutating func endOfActiveHoursIsDue() -> Bool {
        guard !summaryShown, count > 0 else { return false }
        summaryShown = true
        return true
    }

    mutating func activeHoursStarted() {
        summaryShown = false
    }
}
