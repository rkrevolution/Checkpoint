import AppKit
import Carbon.HIToolbox
import Combine
import os.log
import ServiceManagement

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "AppDelegate")

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Owned Objects
    private let settings = AppSettings()
    let appState = AppState()
    let scheduleManager = ScheduleManager()
    let questionBank = QuestionBank()
    let focusObserver = FocusModeObserver()
    let responseLog = ResponseLog()
    let customStore = CustomQuestionStore()
    let objectiveTracker = ObjectiveTracker(
        defaults: AppDelegate.dataDefaults, sessionsURL: AppDelegate.dataURL("sessions.jsonl"))
    let parkedThoughts = ParkedThoughts(
        defaults: AppDelegate.dataDefaults, url: AppDelegate.dataURL("parked.jsonl"))
    private var heartbeatTimer: Timer?
    /// Set once launch setup is done, so the stall check doesn't fire before the timer starts
    private var launchFinished = false
    private var pauseHotKey: GlobalHotKey?
    let callDetector = CallDetector()
    /// A check-in came due during a call; show it (quietly) when the call ends (#1)
    private(set) var checkInHeldForCall = false
    /// True while no keyboard or mouse input for `idleThreshold` (counted as away for time on objective)
    private var isIdle = false
    /// When the current away period began, for the welcome-back prompt
    private var awayStartedAt: Date?
    private static let welcomeBackAfter: TimeInterval = 60 * 60
    private static let idleThreshold: TimeInterval = 5 * 60
    var checkpointTimer: CheckpointTimer?
    private var snoozeTimer: DispatchSourceTimer?
    private var windowController: CheckpointWindowController?
    private var welcomeController: WelcomeWindowController?
    private var objectiveController: ObjectivePromptController?
    private var statusItemController: StatusItemController?
    private var todayController: TodayWindowController?
    private var howItWorksController: HowItWorksWindowController?
    private lazy var focusPill = FocusPillController(tracker: objectiveTracker) { [weak self] in
        self?.updateObjectiveFromMenu()
    }
    lazy var commands = AppCommands(
        changeObjective: { [weak self] in self?.updateObjectiveFromMenu() },
        showHowItWorks: { [weak self] in self?.showHowItWorks() },
        diagnostics: { [weak self] in self?.diagnostics() ?? [] }
    )
    private let transitionToast = TransitionToast()
    private var cancellables = Set<AnyCancellable>()
    private var todayCheckpointCount = 0
    private var lastCheckpointDate: Date?
    /// Start of the stretch the checkpoint card reports as "N minutes have passed".
    /// Reset when the timer (re)starts, on return from away, and when a checkpoint is acknowledged.
    private var elapsedSince: Date?
    private var hasShownDaySummary = false

    // MARK: - Data location

    /// Debug builds launched with `-e2eDataDir <path>` (scripts/e2e.sh) keep tracker and parked
    /// data in a throwaway place, so tests never touch the user's real sessions.
    private static let testDataDir: URL? = {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "e2eDataDir") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return nil
    }()

    private static let dataDefaults: UserDefaults = {
        guard testDataDir != nil else { return .standard }
        let suite = "RkRev.Checkpoint.e2e"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }()

    private static func dataURL(_ name: String) -> URL {
        testDataDir?.appendingPathComponent(name) ?? JSONLinesFile<ParkedThought>.appSupportURL(name)
    }

    private static var isUnitTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When hosting unit tests, don't start the app (it would touch real user data)
        guard !Self.isUnitTestHost else { return }

        let loginStatus = SMAppService.mainApp.status
        log.notice("applicationDidFinishLaunching — loginItem=\(loginStatus.rawValue == 1 ? "enabled" : "not enabled") (status=\(loginStatus.rawValue))")

        // Convert the old ±seconds jitter setting. Defaults aren't registered: each setting's
        // default lives in AppSettings (#16).
        Randomness.migrate()

        // Time on the current objective (#24): continue today's session, if any, then keep it in sync.
        // No session today means the objective prompt appears below.
        objectiveTracker.resume()
        observeObjectiveChanges()
        observeFocusPill()

        // 1. Give QuestionBank access to custom questions
        questionBank.customStore = customStore

        // 2. Wire Focus observer → AppState. Only enter focusModeActive when Focus actually holds
        // check-ins back, so the menu bar never says "Focus" while they keep coming (#50).
        focusObserver.onFocusChanged = { [weak self] isActive in
            guard let self else { return }
            let blocks = CheckInGate.focusBlocks(isFocusActive: isActive, respectFocus: self.settings.respectFocus)
            // Only move between idle and focusModeActive; never override a manual pause,
            // a snooze, or an open checkpoint.
            if blocks, self.appState.state == .idle {
                self.appState.transition(to: .focusModeActive)
            } else if !blocks, self.appState.state == .focusModeActive {
                self.appState.transition(to: .idle)
            }
        }
        focusObserver.startObserving()

        #if DEBUG
        // Make Debug copies unmistakable next to an installed release copy
        NSApp.dockTile.badgeLabel = "DEV"
        #endif
        log.notice("\(AppInfo.displayString, privacy: .public)")
        log.notice("Check-ins \(ScreenCapturePrivacy.statusText(), privacy: .public)")

        // 5. Setup menu bar status item (running indicator + countdown)
        let sic = StatusItemController(appDelegate: self)
        sic.setup()
        statusItemController = sic

        // 6. Pause while the user is away: system sleep, display sleep, screensaver, screen lock
        observeAwayEvents()
        #if DEBUG
        observeDebugCommands()
        #endif

        // ⌃⌥⌘P pauses or resumes from any app (#15)
        pauseHotKey = GlobalHotKey(
            keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey | cmdKey
        ) { [weak self] in
            self?.togglePause()
        }

        // Hold check-ins while the microphone or camera is in use (#1)
        callDetector.onChange = { [weak self] inCall in self?.callChanged(inCall: inCall) }
        callDetector.start()

        // 7. Observe UserDefaults changes to restart timer when interval changes
        observeSettingsChanges()

        // 9. First launch: show welcome. Otherwise: start timer immediately.
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        log.notice("hasLaunchedBefore=\(hasLaunchedBefore)")
        if hasLaunchedBefore {
            // Only ask when there's no objective for today; otherwise just keep going (U1)
            if objectiveTracker.current == nil {
                showObjectivePrompt()
            } else {
                startTimer()
            }
        } else {
            showWelcome()
        }

        launchFinished = true
        statusItemController?.updateDisplay()
    }

    // MARK: - Welcome & Objective

    private func showWelcome() {
        let wc = WelcomeWindowController { [weak self] interval in
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            self?.welcomeController = nil
            self?.showObjectivePrompt()
        }
        welcomeController = wc
        wc.show()
    }

    private func showObjectivePrompt() {
        log.notice("showObjectivePrompt")
        // Start right away: the prompt is optional and can end up buried behind other windows
        if checkpointTimer == nil {
            startTimer()
        }
        let hour = Calendar.current.component(.hour, from: Date())
        presentObjectivePrompt(greeting: hour < 12 ? "Good morning" : "Welcome back") {
            log.notice("Objective prompt dismissed")
        }
    }

    /// "You were on: Report · 1 h 20 min today", for the welcome-back prompt.
    private func welcomeBackContext() -> String? {
        let objective = objectiveTracker.current?.objective
            ?? UserDefaults.standard.string(forKey: "currentObjective") ?? ""
        guard !objective.isEmpty else { return nil }
        let today = ObjectiveTotals.byObjective(objectiveTracker.todaySessions(), at: Date())
            .first { ObjectiveName.same($0.objective, objective) }
        if let today, today.seconds >= 60 {
            return "You were on: \(objective) · \(DurationText.long(today.seconds)) today"
        }
        return "Last: \(objective)"
    }

    /// Opens the "What are you working on?" prompt with recent objectives and the current
    /// estimate, records the estimate on Start, then runs `onDone`.
    private func presentObjectivePrompt(greeting: String? = nil, onDone: @escaping () -> Void) {
        let session = objectiveTracker.current
        let oc = ObjectivePromptController(
            recentObjectives: objectiveTracker.recentObjectives(limit: 10),
            initialEstimate: session?.estimateMinutes,
            greeting: greeting,
            context: greeting == nil ? nil : welcomeBackContext()
        ) { [weak self] in
            self?.objectiveController = nil
            onDone()
        }
        oc.onEstimate = { [weak self] minutes in
            guard let self else { return }
            // Apply the new objective now (the defaults observer runs later) so the
            // estimate lands on the right session
            self.objectiveTracker.objectiveChanged(to: UserDefaults.standard.string(forKey: "currentObjective") ?? "")
            self.objectiveTracker.estimateChanged(to: minutes)
        }
        objectiveController = oc
        oc.show()
    }

    /// A check-in just ended (answered or dropped). The next one is a full interval from now,
    /// so time spent snoozed, held for a call or with the card open doesn't shorten the gap (#52).
    private func startNextInterval(after reason: String) {
        log.notice("Check-in ended (\(reason, privacy: .public)): next interval starts now")
        checkpointTimer?.restart(interval: settings.checkInInterval)
    }

    private func startTimer() {
        let effectiveInterval = settings.checkInInterval
        log.notice("━━━ TIMER STARTING ━━━")
        log.notice("  Base interval: \(Int(effectiveInterval))s (\(Int(effectiveInterval)/60)min)")
        log.notice("  Randomness: \(self.settings.randomness.label(for: effectiveInterval), privacy: .public)")
        log.notice("  Active hours: \(self.settings.useActiveHours ? "on" : "off (always active)")")
        let timer = CheckpointTimer(settings: settings)
        timer.onFire = { [weak self] in self?.handleTimerFire() }
        // Remember when the next check-in is due, so a relaunch keeps the schedule
        timer.onSchedule = { due in AppDelegate.dataDefaults.set(due, forKey: AppDelegate.nextCheckInDueKey) }
        let resume = CheckpointTimer.resumeDelay(
            savedDue: AppDelegate.dataDefaults.object(forKey: AppDelegate.nextCheckInDueKey) as? Date,
            now: Date(), interval: effectiveInterval)
        if let resume { log.notice("  Keeping the schedule from before the relaunch: first check-in in \(Int(resume))s") }
        timer.start(interval: effectiveInterval, firstFireIn: resume)
        checkpointTimer = timer
        elapsedSince = Date()
    }

    private static let nextCheckInDueKey = "nextCheckInDue"

    // MARK: - Away (Sleep / Display Sleep / Screensaver / Lock)

    private enum AwayReason: String {
        case systemSleep, displaySleep, screensaver, screenLocked
    }

    /// Checkpoints never fire while any of these are active.
    private var awayReasons = Set<AwayReason>()

    private func observeAwayEvents() {
        let events: [(NotificationCenter, String, AwayReason, Bool)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification.rawValue, .systemSleep, true),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification.rawValue, .systemSleep, false),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification.rawValue, .displaySleep, true),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification.rawValue, .displaySleep, false),
            (DistributedNotificationCenter.default(), "com.apple.screensaver.didstart", .screensaver, true),
            (DistributedNotificationCenter.default(), "com.apple.screensaver.didstop", .screensaver, false),
            (DistributedNotificationCenter.default(), "com.apple.screenIsLocked", .screenLocked, true),
            (DistributedNotificationCenter.default(), "com.apple.screenIsUnlocked", .screenLocked, false),
        ]
        for (center, name, reason, isStart) in events {
            center.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if isStart { self?.beginAway(reason) } else { self?.endAway(reason) }
                }
            }
        }
    }

    private func beginAway(_ reason: AwayReason) {
        let wasAway = !awayReasons.isEmpty
        awayReasons.insert(reason)
        defer { updateFocusPill() }
        if !wasAway { awayStartedAt = Date() }
        log.notice("━━━ AWAY: \(reason.rawValue, privacy: .public) (reasons=\(self.awayReasons.map(\.rawValue), privacy: .public)) ━━━")
        guard !wasAway else { return }

        checkInHeldForCall = false

        objectiveTracker.beginAway()

        checkpointTimer?.stop()
        snoozeTimer?.cancel()
        snoozeTimer = nil

        // Pull down any visible checkpoint (and its overlays) so nothing sits over the
        // screensaver/lock screen or is left behind when the user returns.
        if let wc = windowController {
            log.notice("  Dismissing open checkpoint window")
            wc.dismissImmediately()
            windowController = nil
        }
        if appState.state != .paused {
            appState.transition(to: .idle)
        }
    }

    private func endAway(_ reason: AwayReason) {
        guard awayReasons.remove(reason) != nil else { return }
        log.notice("━━━ BACK: \(reason.rawValue, privacy: .public) (remaining=\(self.awayReasons.map(\.rawValue), privacy: .public)) ━━━")
        guard awayReasons.isEmpty else { return }

        // While paused the clock stays stopped until Resume
        if appState.state != .paused {
            objectiveTracker.endAway()
        }

        // Back after a long break: a welcome-back prompt to pick up (or change) the objective
        if appState.state != .paused, let since = awayStartedAt,
           Date().timeIntervalSince(since) >= Self.welcomeBackAfter,
           objectiveController == nil, welcomeController == nil {
            log.notice("Back after \(Int(Date().timeIntervalSince(since) / 60)) min: welcome back")
            presentObjectivePrompt(greeting: "Welcome back") {}
        }
        awayStartedAt = nil
        updateFocusPill()

        // If user had manually paused, respect that
        if appState.state == .paused {
            log.notice("  User was paused before going away, staying paused")
            return
        }

        // Restart fresh
        appState.transition(to: .idle)
        checkpointTimer?.restart(interval: settings.checkInInterval)
        elapsedSince = Date()
        log.notice("  Timer restarted with interval \(Int(self.settings.checkInInterval))s")
    }

    // MARK: - Timer Fire

    private func resetDayCountersIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if let lastDate = lastCheckpointDate, Calendar.current.startOfDay(for: lastDate) != today {
            todayCheckpointCount = 0
            hasShownDaySummary = false
        }
    }

    /// Everything `CheckInGate` needs, as of now.
    private func gateConditions() -> CheckInGate.Conditions {
        CheckInGate.Conditions(
            state: appState.state,
            isAway: !awayReasons.isEmpty,
            scheduleAllows: scheduleManager.shouldFire(),
            withinActiveHours: scheduleManager.isWithinActiveHours(),
            isFocusActive: focusObserver.isFocusActive,
            respectFocus: settings.respectFocus,
            isOnCall: callDetector.isInCall,
            holdDuringCalls: settings.holdDuringCalls
        )
    }

    /// The interval timer fired, or a check-in held for a call is being delivered (`afterCall`,
    /// shown without sound).
    private func handleTimerFire(afterCall: Bool = false) {
        log.notice("handleTimerFire: currentState=\(String(describing: self.appState.state))")
        // Reset daily counters on day boundary regardless of whether checkpoint fires
        resetDayCountersIfNeeded()

        let block = CheckInGate.block(.scheduled, gateConditions())
        log.notice("Gate: \(block.map { "\($0)" } ?? "show", privacy: .public)")
        switch block {
        case nil:
            settle(to: .idle)
            fireCheckpoint(playSound: !afterCall)
        case .away:
            log.notice("User away (\(self.awayReasons.map(\.rawValue), privacy: .public)), skipping")
        case .paused, .inProgress:
            log.notice("Not idle, skipping. state=\(String(describing: self.appState.state))")
        case .schedule(let outsideActiveHours):
            if outsideActiveHours {
                showDaySummaryIfNeeded()
                settle(to: .outsideHours)
            } else {
                settle(to: .idle)
            }
        case .focus:
            settle(to: .focusModeActive)
        case .call:
            // Show it when the call ends (#1)
            log.notice("Check-in held: on a call")
            settle(to: .idle)
            checkInHeldForCall = true
        }
    }

    /// Moves between the waiting states (idle, outside hours, Focus). Coming back from outside
    /// active hours starts a new stretch: the off-hours gap isn't reported as elapsed time.
    private func settle(to waiting: CheckpointState) {
        if appState.state == .outsideHours, waiting != .outsideHours {
            log.notice("Recovering from outsideHours")
            hasShownDaySummary = false
            elapsedSince = nil
        }
        appState.transition(to: waiting)
    }

    /// Builds and presents a checkpoint. Callers ask `CheckInGate` first.
    private func fireCheckpoint(playSound: Bool = true) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        log.notice("━━━ CHECKPOINT FIRING ━━━")
        log.notice("  Time: \(formatter.string(from: Date()))")
        appState.transition(to: .triggered)

        let questions = questionBank.selectQuestions(
            count: settings.questionsPerCheckIn,
            recentCategoryIds: appState.recentCategoryIds
        )

        // timestamp and elapsed time are filled in at presentation (see presentCheckpoint)
        let session = CheckpointSession(
            id: UUID(),
            timestamp: Date(),
            intervalSeconds: 0,
            questionsShown: questions,
            responses: questions.map { QuestionResponse(questionId: $0.id, text: "") },
            outcome: .completed
        )

        appState.recordShownCategories(questions.map(\.categoryId))

        // Track daily checkpoint count and objectives
        todayCheckpointCount += 1
        lastCheckpointDate = Date()


        // Play sound if enabled
        if playSound, settings.playSound {
            NSSound(named: NSSound.Name(settings.soundName))?.play()
        }

        log.notice("Presenting checkpoint: \(questions.count) questions")
        presentCheckpoint(session: session, snoozeCount: 0)
    }

    private func presentCheckpoint(session original: CheckpointSession, snoozeCount: Int) {
        log.notice("presentCheckpoint: snoozeCount=\(snoozeCount)")
        guard awayReasons.isEmpty else {
            log.notice("User away, not presenting")
            appState.transition(to: .idle)
            return
        }
        appState.transition(to: .presenting)

        // Show the current time and real elapsed time, also when re-presenting after a snooze
        let now = Date()
        let elapsed = elapsedSince.map { Int(now.timeIntervalSince($0)) } ?? Int(settings.checkInInterval)
        let session = CheckpointSession(
            id: original.id,
            timestamp: now,
            intervalSeconds: elapsed,
            questionsShown: original.questionsShown,
            responses: original.responses,
            outcome: original.outcome
        )

        // Only show an objective that's being timed; otherwise the card asks what you're on (#75)
        let objective = objectiveTracker.current?.objective ?? ""
        let wc = CheckpointWindowController(
            session: session,
            currentObjective: objective,
            checkpointNumber: todayCheckpointCount,
            objectiveSession: objectiveTracker.current,
            recentObjectives: objectiveTracker.recentObjectives(limit: 10),
            allowSnooze: settings.allowsSnooze(after: snoozeCount),
            onDone: { [weak self] completed, updatedObjective in
                let formatter = DateFormatter()
                formatter.timeStyle = .medium
                log.notice("━━━ CHECKPOINT COMPLETED ━━━")
                log.notice("  Response: \(completed.checkInResponse?.rawValue ?? "none", privacy: .public) at \(formatter.string(from: Date()))")
                log.notice("  Objective updated: \(updatedObjective != nil ? "yes" : "no")")
                self?.windowController = nil
                self?.elapsedSince = Date()
                // Save updated objective if user changed it, show transition toast
                if let updated = updatedObjective, !updated.isEmpty {
                    UserDefaults.standard.set(updated, forKey: "currentObjective")
                    // Start timing now: re-picking the same text as a stale objective leaves the
                    // setting unchanged, so its observer wouldn't fire (#75)
                    self?.objectiveTracker.objectiveChanged(to: updated)
                    self?.transitionToast.show(from: objective, to: updated)
                }
                if let thought = completed.parkedThought {
                    self?.parkedThoughts.park(thought, objective: self?.objectiveTracker.current?.objective)
                }
                if self?.settings.logResponses == true {
                    try? self?.responseLog.append(completed)
                }
                self?.appState.transition(to: .idle)
                self?.startNextInterval(after: "answered")
            },
            onSnooze: { [weak self] in
                let formatter = DateFormatter()
                formatter.timeStyle = .medium
                log.notice("━━━ CHECKPOINT SNOOZED ━━━")
                log.notice("  User tapped 'Not now' at \(formatter.string(from: Date()))")
                self?.windowController = nil
                self?.handleSnooze(session: session, snoozeCount: snoozeCount)
            }
        )
        windowController = wc
        wc.showWithFade()

        // Verify modal appeared
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let w = wc.window, w.isVisible {
                log.notice("✓ Modal window visible on screen")
            } else {
                log.error("✗ Modal window NOT visible — something blocked it")
            }
        }
    }

    // MARK: - Snooze

    private func handleSnooze(session: CheckpointSession, snoozeCount: Int) {
        log.notice("  Snooze #\(snoozeCount + 1), will re-present in \(self.settings.snoozeMinutes)min")
        let newCount = snoozeCount + 1

        // Log the snooze
        if settings.logResponses {
            // Log each snooze as its own entry so History never sees duplicate IDs
            let snoozed = CheckpointSession(
                id: UUID(),
                timestamp: Date(),
                intervalSeconds: session.intervalSeconds,
                questionsShown: session.questionsShown,
                responses: session.responses,
                outcome: .snoozed
            )
            try? responseLog.append(snoozed)
        }

        // Max snoozes reached: either drop this checkpoint, or ("forceModal") fall through
        // and re-present after the snooze without a "Not now" option.
        if !settings.allowsSnooze(after: newCount), settings.afterMaxSnooze == .autoDismiss {
            appState.transition(to: .idle)
            startNextInterval(after: "snooze limit reached")
            return
        }

        let snoozeSecs = settings.snoozeMinutes * 60
        let until = Date().addingTimeInterval(TimeInterval(snoozeSecs))
        appState.transition(to: .snoozed(until: until, count: newCount))

        // Start snooze mini-timer
        snoozeTimer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + .seconds(snoozeSecs))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.snoozeTimer = nil
            switch CheckInGate.block(.snoozeReturn, self.gateConditions()) {
            case nil:
                self.presentCheckpoint(session: session, snoozeCount: newCount)
            case .call:
                log.notice("Snoozed check-in held: on a call")
                self.appState.transition(to: .idle)
                self.checkInHeldForCall = true
            case .schedule, .focus:
                log.notice("Snoozed checkpoint dropped: schedule or Focus no longer allows it")
                self.appState.transition(to: .idle)
                self.startNextInterval(after: "snoozed check-in dropped")
            case .away, .paused, .inProgress:
                break  // cancelled or replaced in the meantime
            }
        }
        source.resume()
        snoozeTimer = source
    }

    // MARK: - Day Summary

    private func showDaySummaryIfNeeded() {
        guard !hasShownDaySummary, todayCheckpointCount > 0 else { return }
        hasShownDaySummary = true

        showToday(headline: "End of active hours")
    }

    // MARK: - Today window

    @objc func showHowItWorks() {
        let controller = howItWorksController ?? HowItWorksWindowController()
        howItWorksController = controller
        controller.show()
    }

    @objc func showTodayFromMenu() {
        showToday(headline: nil)
    }

    private func showToday(headline: String?) {
        if let window = todayController?.window, window.isVisible, headline == nil {
            todayController?.show()
            return
        }
        todayController?.close()
        let controller = TodayWindowController(
            tracker: objectiveTracker,
            parked: parkedThoughts,
            loadCheckIns: { [weak self] in (try? self?.responseLog.loadAll()) ?? [] },
            headline: headline
        )
        todayController = controller
        controller.show()
    }

    private func observeObjectiveChanges() {
        UserDefaults.standard.publisher(for: \.currentObjective)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] objective in self?.objectiveTracker.objectiveChanged(to: objective ?? "") }
            .store(in: &cancellables)
        UserDefaults.standard.publisher(for: \.currentIfThenPlan)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] plan in self?.objectiveTracker.ifThenPlanChanged(to: plan) }
            .store(in: &cancellables)

        // Heartbeat lets the tracker exclude time the app wasn't running after a relaunch;
        // the idle check excludes time at the desk with no input before the display sleeps
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Before the heartbeat, which would move "last seen" past midnight
                if self.objectiveTracker.endIfFromEarlierDay() { self.newDayStarted() }
                self.objectiveTracker.heartbeat()
                self.checkIdle()
            }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    /// The app ran past midnight with a session open (#51): yesterday's session has ended, so ask
    /// what today is about. Not while away or paused (Resume and a long absence bring up
    /// "Welcome back"); either way, until an objective is set the next card asks for one
    /// instead of showing yesterday's.
    private func newDayStarted() {
        resetDayCountersIfNeeded()
        guard awayReasons.isEmpty, appState.state != .paused,
              objectiveController == nil, welcomeController == nil else { return }
        showObjectivePrompt()
    }

    /// Counts long stretches without keyboard or mouse input as away (backdated to the last input).
    /// Only affects time on objective, not check-in scheduling.
    private func checkIdle() {
        // Sleep/lock/screensaver and pause already stop the clock
        guard awayReasons.isEmpty, appState.state != .paused else { return }
        // On a call you're working even without typing
        if callDetector.isInCall {
            if isIdle {
                isIdle = false
                objectiveTracker.endAway()
            }
            return
        }
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if !isIdle, idle >= Self.idleThreshold {
            isIdle = true
            objectiveTracker.beginAway(at: Date().addingTimeInterval(-idle))
            log.notice("Idle for \(Int(idle))s: not counting it as time on objective")
        } else if isIdle, idle < Self.idleThreshold {
            isIdle = false
            objectiveTracker.endAway(at: Date().addingTimeInterval(-idle))
            log.notice("Input resumed")
        }
    }

    /// Clicking the Dock icon (or opening the app again from Finder or Spotlight) opens
    /// Settings when nothing else is showing: it's the app's main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        log.notice("Reopen: opening Settings")
        openPreferences()
        return false
    }

    // MARK: - Diagnostics

    /// When the next check-in will appear, or why none is scheduled. For Diagnostics and the
    /// Debug menu only: showing it in everyday UI would let users brace for check-ins.
    var nextCheckInDescription: String {
        if !awayReasons.isEmpty { return "none while away" }
        switch appState.state {
        case .paused: return "none while paused"
        case .presenting, .triggered: return "a check-in is showing now"
        case .snoozed(let until, _): return "snoozed until \(until.formatted(date: .omitted, time: .standard))"
        default: break
        }
        guard let next = checkpointTimer?.nextFireDate else { return "timer not running" }
        let mins = max(0, Int(next.timeIntervalSinceNow / 60))
        var text = "\(next.formatted(date: .omitted, time: .standard)) (in about \(mins) min)"
        if checkInHeldForCall { text += ", one held until the call ends" }
        return text
    }

    func diagnostics() -> [(label: String, value: String)] {
        let respectFocus = settings.respectFocus
        let login: String
        switch SMAppService.mainApp.status {
        case .enabled: login = "on"
        case .requiresApproval: login = "needs approval in System Settings › General › Login Items"
        case .notRegistered: login = "off"
        case .notFound: login = "not found (unsigned or moved build?)"
        @unknown default: login = "unknown"
        }
        return [
            ("Next check-in", nextCheckInDescription),
            ("Last check-in", lastCheckpointDate?.formatted(date: .omitted, time: .standard) ?? "none since launch"),
            ("State", String(describing: appState.state)),
            ("Stall check", stallReason ?? "OK"),
            ("Away", awayReasons.isEmpty ? "no" : awayReasons.map(\.rawValue).sorted().joined(separator: ", ")),
            ("Idle (5+ min)", isIdle ? "yes" : "no"),
            ("On a call", callDetector.isInCall ? "yes" : "no"),
            ("Focus detected", (focusObserver.isFocusActive ? "yes" : "no") + (respectFocus ? "" : " (not respected)")),
            ("Start at Login", login),
            ("Screen capture", "Check-ins " + ScreenCapturePrivacy.statusText()),
            ("Interval", {
                let interval = settings.checkInInterval
                return "every \(DurationText.long(interval)), randomness \(settings.randomness.label(for: interval))"
            }()),
            ("Version", AppInfo.displayString),
            ("Data folder", JSONLinesFile<ParkedThought>.appSupportURL("").path),
        ]
    }

    // MARK: - Focus pill

    /// Shows or hides the always-visible focus strip to match the setting and current state.
    private func updateFocusPill() {
        focusPill.setVisible(FocusPillPolicy.shouldShow(
            enabled: settings.showFocusPill,
            hasObjective: objectiveTracker.current != nil,
            isPaused: appState.state == .paused,
            isAway: !awayReasons.isEmpty
        ))
    }

    private func observeFocusPill() {
        objectiveTracker.$current.map { $0 == nil }.removeDuplicates()
            .combineLatest(appState.$state.map { $0 == .paused }.removeDuplicates(),
                           UserDefaults.standard.publisher(for: \.showFocusPill).removeDuplicates())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateFocusPill() }
            .store(in: &cancellables)
    }

    @objc func toggleFocusPill() {
        settings.showFocusPill.toggle()
    }

    // MARK: - Calls (#1)

    private func callChanged(inCall: Bool) {
        statusItemController?.updateDisplay()
        guard !inCall, checkInHeldForCall else { return }
        checkInHeldForCall = false
        // The held check-in shows now, quietly, if the gate still allows it
        log.notice("Call ended: showing the held check-in")
        handleTimerFire(afterCall: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        objectiveTracker.heartbeat()
    }

    // MARK: - Parked thoughts (#34)

    @objc func parkThoughtFromMenu() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Park a thought"
        alert.informativeText = "Write it down to deal with later, then get back to what you were doing."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "e.g. reply to Sam about Friday"
        alert.accessoryView = field
        alert.addButton(withTitle: "Park It")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            parkedThoughts.park(field.stringValue, objective: objectiveTracker.current?.objective)
        }
    }

    @objc func markParkedThoughtDone(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        parkedThoughts.markDone(id)
    }

    // MARK: - Stall detection (#25)

    var isAway: Bool { !awayReasons.isEmpty }
    var lastCheckInDate: Date? { lastCheckpointDate }

    /// Why check-ins have stopped when they shouldn't have, or nil if all is well.
    /// A time-blind user won't notice missing check-ins, so the menu bar shows this.
    var stallReason: String? {
        guard launchFinished, awayReasons.isEmpty, welcomeController == nil else { return nil }
        let now = Date()
        switch appState.state {
        case .idle:
            guard let next = checkpointTimer?.nextFireDate else { return "the timer isn't running" }
            if next < now.addingTimeInterval(-90) { return "a check-in is overdue" }
        case .snoozed(let until, _):
            if until < now.addingTimeInterval(-90) { return "a snoozed check-in didn't come back" }
        case .presenting:
            if windowController?.window?.isVisible != true { return "the check-in card isn't on screen" }
        default:
            break
        }
        return nil
    }

    func logStall(_ reason: String) {
        log.error("Check-ins stalled: \(reason, privacy: .public) state=\(String(describing: self.appState.state), privacy: .public)")
    }

    /// Menu action shown with the stall warning: clears whatever is stuck and starts fresh.
    @objc func restartCheckIns() {
        log.notice("Restarting check-ins")
        windowController?.dismissImmediately()
        windowController = nil
        snoozeTimer?.cancel()
        snoozeTimer = nil
        appState.transition(to: .idle)
        if checkpointTimer == nil {
            startTimer()
        } else {
            checkpointTimer?.restart(interval: settings.checkInInterval)
            elapsedSince = Date()
        }
        statusItemController?.updateDisplay()
    }

    private func observeSettingsChanges() {
        UserDefaults.standard
            .publisher(for: \.checkpointInterval)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newInterval in
                guard let self, newInterval > 0 else { return }
                self.checkpointTimer?.restart(interval: TimeInterval(newInterval))
            }
            .store(in: &cancellables)
    }

    // MARK: - Dock Menu

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        switch appState.state {
        case .paused:
            menu.addItem(withTitle: "Resume Checkpoints", action: #selector(resumeCheckpoints), keyEquivalent: "")
        default:
            menu.addItem(withTitle: "Pause Checkpoints", action: #selector(pauseCheckpoints), keyEquivalent: "")
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openPreferences), keyEquivalent: ",")

        return menu
    }

    /// Global shortcut: pause (dismissing any open card) or resume.
    private func togglePause() {
        if appState.state == .paused {
            log.notice("Shortcut: resume")
            resumeCheckpoints()
        } else {
            log.notice("Shortcut: pause")
            pauseCheckpoints()
        }
    }

    /// Pausing stops check-ins and the clock on the current objective; any open card closes (#49).
    @objc private func pauseCheckpoints() {
        windowController?.dismissImmediately()
        windowController = nil
        checkpointTimer?.stop()
        snoozeTimer?.cancel()
        snoozeTimer = nil
        objectiveTracker.beginAway()
        appState.transition(to: .paused)
    }

    @objc private func resumeCheckpoints() {
        // Re-prompt for objective on resume, then restart timer
        presentObjectivePrompt(greeting: "Welcome back") { [weak self] in
            guard let self else { return }
            self.checkpointTimer?.restart(interval: self.settings.checkInInterval)
            self.elapsedSince = Date()
            self.objectiveTracker.endAway()  // the clock starts again
            self.appState.transition(to: .idle)
        }
    }

    @objc func openPreferences() {
        // macOS 14+ ignores the old `showSettingsWindow:` action, so trigger the app menu's
        // own Settings… item (the one SwiftUI's Settings scene installs) instead.
        NSApp.activate()
        if let appMenu = NSApp.mainMenu?.items.first?.submenu,
           let index = appMenu.items.firstIndex(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command }) {
            appMenu.performActionForItem(at: index)
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    // Called from StatusItemController menu
    @objc func pauseFromMenu() { pauseCheckpoints() }
    @objc func resumeFromMenu() { resumeCheckpoints() }

    @objc func updateObjectiveFromMenu() {
        let oldObjective = UserDefaults.standard.string(forKey: "currentObjective") ?? ""
        presentObjectivePrompt { [weak self] in
            let newObjective = UserDefaults.standard.string(forKey: "currentObjective") ?? ""
            if oldObjective != newObjective {
                self?.transitionToast.show(from: oldObjective, to: newObjective)
            }
        }
    }

    /// Manual check-in: an explicit request, so the gate skips the schedule, Focus and call checks.
    @objc func triggerNow() {
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
        snoozeTimer?.cancel()
        snoozeTimer = nil
        resetDayCountersIfNeeded()
        appState.transition(to: .idle)
        fireCheckpoint()
    }


}

// MARK: - Debug Menu Actions

#if DEBUG
extension AppDelegate {

    var debugScreensaverActive: Bool { awayReasons.contains(.screensaver) }
    var debugScreenLocked: Bool { awayReasons.contains(.screenLocked) }

    /// Goes through the normal fire path (all schedule/Focus/away gates apply).
    @objc func debugCheckInSoon() {
        log.notice("DEBUG: check-in in 10s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.triggerNow()
        }
    }

    @objc func debugToggleScreensaver() {
        debugScreensaverActive ? endAway(.screensaver) : beginAway(.screensaver)
    }

    @objc func debugToggleScreenLock() {
        debugScreenLocked ? endAway(.screenLocked) : beginAway(.screenLocked)
    }

    @objc func debugToggleFocus() {
        focusObserver.debugSetFocus(!focusObserver.isFocusActive)
    }

    /// Commands a test script can send to a Debug build:
    /// `com.rkrev.checkpoint.debug.<command>` as a distributed notification (see scripts/e2e.sh).
    private static let debugCommands = [
        "checkInNow", "acknowledge", "snooze", "pause",
        "focusOn", "focusOff",
        "screensaverStart", "screensaverStop", "lockStart", "lockStop",
        "callStart", "callStop", "timerFire",
    ]

    private func observeDebugCommands() {
        for command in Self.debugCommands {
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.rkrev.checkpoint.debug.\(command)"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.runDebugCommand(command)
                }
            }
        }
    }

    private func runDebugCommand(_ command: String) {
        log.notice("DEBUG command: \(command, privacy: .public)")
        switch command {
        case "checkInNow": triggerNow()
        case "acknowledge": windowController?.debugAcknowledge()
        case "snooze": windowController?.debugSnooze()
        case "pause": pauseCheckpoints()
        case "focusOn": focusObserver.debugSetFocus(true)
        case "focusOff": focusObserver.debugSetFocus(false)
        case "screensaverStart": beginAway(.screensaver)
        case "screensaverStop": endAway(.screensaver)
        case "lockStart": beginAway(.screenLocked)
        case "lockStop": endAway(.screenLocked)
        case "callStart": callDetector.debugOverride = true
        case "callStop": callDetector.debugOverride = false
        case "timerFire": handleTimerFire()
        default: log.error("Unknown debug command: \(command, privacy: .public)")
        }
    }

    @objc func debugResetFirstLaunch() {
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
        log.notice("DEBUG: first-launch flag cleared; Welcome shows on next launch")
    }
}
#endif
