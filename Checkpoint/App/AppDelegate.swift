import AppKit
import Carbon.HIToolbox
import Combine
import os.log
import ServiceManagement

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "AppDelegate")

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Owned Objects
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
    lazy var commands = AppCommands(
        changeObjective: { [weak self] in self?.updateObjectiveFromMenu() },
        showHowItWorks: { [weak self] in self?.showHowItWorks() }
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

        // Register all UserDefaults
        UserDefaults.standard.register(defaults: [
            "checkpointInterval": 2700,
            "activeHoursStart": 8,
            "activeHoursEnd": 18,
            "checkpointsEnabled": true,
            "useActiveHours": false,
            "questionsPerCheckpoint": 1,
            "snoozeMinutes": 5,
            "maxSnoozesPerCheckpoint": 2,
            "afterMaxSnoozeAction": "autoDismiss",
            "jitterRange": 600,
            "playSoundOnCheckpoint": true,
            "soundName": "Glass",
            "respectFocusMode": true,
            "logResponses": true,
            "skipWeekdays": [Int](),
            "disabledQuestionIDs": [String](),
            "showBreathingCue": false,
            "fullScreenCheckpoint": false,
            "holdDuringCalls": true,
            "menuBarDisplay": "objectiveTime",
        ])

        // Time on the current objective (#24): continue today's session, if any, then keep it in sync.
        // No session today means the objective prompt appears below.
        objectiveTracker.resume()
        observeObjectiveChanges()

        // 1. Give QuestionBank access to custom questions
        questionBank.customStore = customStore

        // 2. Wire Focus observer → AppState (always observe; setting checked at fire time)
        focusObserver.onFocusChanged = { [weak self] isActive in
            guard let self else { return }
            // Only move between idle and focusModeActive; never override a manual pause,
            // a snooze, or an open checkpoint.
            if isActive, self.appState.state == .idle {
                self.appState.transition(to: .focusModeActive)
            } else if !isActive, self.appState.state == .focusModeActive {
                self.appState.transition(to: .idle)
            }
        }
        focusObserver.startObserving()

        // 3. Set dock icon programmatically (sun)
        setDockIcon()
        #if DEBUG
        // Make Debug copies unmistakable next to an installed release copy
        NSApp.dockTile.badgeLabel = "DEV"
        #endif
        log.notice("\(AppInfo.displayString, privacy: .public)")

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

        // 8. Observe AppState changes
        appState.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.syncDockMenu() }
            .store(in: &cancellables)

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

    private func startTimer() {
        let interval = TimeInterval(UserDefaults.standard.integer(forKey: "checkpointInterval"))
        let effectiveInterval = interval > 0 ? interval : 2700
        let jitter = UserDefaults.standard.integer(forKey: "jitterRange")
        log.notice("━━━ TIMER STARTING ━━━")
        log.notice("  Base interval: \(Int(effectiveInterval))s (\(Int(effectiveInterval)/60)min)")
        log.notice("  Jitter range: ±\(jitter/60)min")
        log.notice("  Active hours: \(UserDefaults.standard.bool(forKey: "useActiveHours") ? "on" : "off (always active)")")
        let timer = CheckpointTimer()
        timer.onFire = { [weak self] in self?.handleTimerFire() }
        timer.start(interval: effectiveInterval)
        checkpointTimer = timer
        elapsedSince = Date()
    }

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

        // If user had manually paused, respect that
        if appState.state == .paused {
            log.notice("  User was paused before going away, staying paused")
            return
        }

        // Restart fresh
        appState.transition(to: .idle)
        let interval = TimeInterval(UserDefaults.standard.integer(forKey: "checkpointInterval"))
        let effectiveInterval = interval > 0 ? interval : 2700
        checkpointTimer?.restart(interval: effectiveInterval)
        elapsedSince = Date()
        log.notice("  Timer restarted with interval \(Int(effectiveInterval))s")
    }

    // MARK: - Timer Fire

    private func resetDayCountersIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if let lastDate = lastCheckpointDate, Calendar.current.startOfDay(for: lastDate) != today {
            todayCheckpointCount = 0
            hasShownDaySummary = false
        }
    }

    private func handleTimerFire(afterCall: Bool = false) {
        log.notice("handleTimerFire: currentState=\(String(describing: self.appState.state))")

        guard awayReasons.isEmpty else {
            log.notice("User away (\(self.awayReasons.map(\.rawValue), privacy: .public)), skipping")
            return
        }

        // Reset daily counters on day boundary regardless of whether checkpoint fires
        resetDayCountersIfNeeded()

        // Recover from outsideHours when hours become active again
        if appState.state == .outsideHours, scheduleManager.isWithinActiveHours() {
            log.notice("Recovering from outsideHours → idle")
            appState.transition(to: .idle)
            hasShownDaySummary = false
            // Don't report the off-hours gap as elapsed time; fall back to the interval
            elapsedSince = nil
        }

        // Focus is re-checked below on every fire, so don't stay stuck in focusModeActive
        // (e.g. after "Respect Focus" is turned off while Focus is on)
        if appState.state == .focusModeActive {
            appState.transition(to: .idle)
        }

        // Only fire from idle state
        guard appState.state == .idle else {
            log.notice("Not idle, skipping. state=\(String(describing: self.appState.state))")
            if !scheduleManager.isWithinActiveHours() {
                showDaySummaryIfNeeded()
                appState.transition(to: .outsideHours)
            }
            return
        }

        let withinHours = scheduleManager.isWithinActiveHours()
        let shouldFire = scheduleManager.shouldFire()
        let focusActive = focusObserver.isFocusActive
        let respectFocus = UserDefaults.standard.bool(forKey: "respectFocusMode")
        log.notice("Gate checks: withinHours=\(withinHours), shouldFire=\(shouldFire), focusActive=\(focusActive), respectFocus=\(respectFocus)")

        // Check schedule (active hours, weekday skips, blackout, DND)
        guard shouldFire else {
            log.notice("shouldFire=false, checkpoint suppressed")
            if !withinHours {
                showDaySummaryIfNeeded()
                appState.transition(to: .outsideHours)
            }
            return
        }

        // Check Focus mode
        if respectFocus, focusActive {
            log.notice("Focus mode active, checkpoint suppressed")
            appState.transition(to: .focusModeActive)
            return
        }

        // On a call: hold the check-in and show it when the call ends (#1)
        if holdsForCall {
            log.notice("Check-in held: on a call")
            checkInHeldForCall = true
            return
        }

        log.notice("  All gates passed ✓")
        fireCheckpoint(playSound: !afterCall)
    }

    /// Builds and presents a checkpoint. Callers are responsible for the schedule/Focus gates.
    private func fireCheckpoint(playSound: Bool = true) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        log.notice("━━━ CHECKPOINT FIRING ━━━")
        log.notice("  Time: \(formatter.string(from: Date()))")
        appState.transition(to: .triggered)

        let count = UserDefaults.standard.integer(forKey: "questionsPerCheckpoint")
        let questions = questionBank.selectQuestions(
            count: count > 0 ? count : 1,
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
        if playSound, UserDefaults.standard.bool(forKey: "playSoundOnCheckpoint") {
            let soundName = UserDefaults.standard.string(forKey: "soundName") ?? "Glass"
            NSSound(named: NSSound.Name(soundName))?.play()
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

        let interval = UserDefaults.standard.integer(forKey: "checkpointInterval")

        // Show the current time and real elapsed time, also when re-presenting after a snooze
        let now = Date()
        let elapsed = elapsedSince.map { Int(now.timeIntervalSince($0)) } ?? (interval > 0 ? interval : 2700)
        let session = CheckpointSession(
            id: original.id,
            timestamp: now,
            intervalSeconds: elapsed,
            questionsShown: original.questionsShown,
            responses: original.responses,
            outcome: original.outcome
        )

        let objective = UserDefaults.standard.string(forKey: "currentObjective") ?? ""
        let maxSnoozes = UserDefaults.standard.integer(forKey: "maxSnoozesPerCheckpoint")

        let wc = CheckpointWindowController(
            session: session,
            currentObjective: objective,
            checkpointNumber: todayCheckpointCount,
            objectiveSession: objectiveTracker.current,
            recentObjectives: objectiveTracker.recentObjectives(limit: 10),
            allowSnooze: maxSnoozes == 0 || snoozeCount < maxSnoozes,
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
                    let old = UserDefaults.standard.string(forKey: "currentObjective") ?? ""
                    UserDefaults.standard.set(updated, forKey: "currentObjective")
                    if old != updated {
                        self?.transitionToast.show(from: old, to: updated)
                    }
                }
                if let thought = completed.parkedThought {
                    self?.parkedThoughts.park(thought, objective: self?.objectiveTracker.current?.objective)
                }
                if UserDefaults.standard.bool(forKey: "logResponses") {
                    try? self?.responseLog.append(completed)
                }
                self?.appState.transition(to: .idle)
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
        let snoozeMin = UserDefaults.standard.integer(forKey: "snoozeMinutes")
        log.notice("  Snooze #\(snoozeCount + 1), will re-present in \(snoozeMin > 0 ? snoozeMin : 5)min")
        let maxSnoozes = UserDefaults.standard.integer(forKey: "maxSnoozesPerCheckpoint")
        let newCount = snoozeCount + 1

        // Log the snooze
        if UserDefaults.standard.bool(forKey: "logResponses") {
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
        if maxSnoozes > 0, newCount >= maxSnoozes,
           (UserDefaults.standard.string(forKey: "afterMaxSnoozeAction") ?? "autoDismiss") == "autoDismiss" {
            appState.transition(to: .idle)
            return
        }

        let snoozeMinutes = UserDefaults.standard.integer(forKey: "snoozeMinutes")
        let snoozeSecs = snoozeMinutes > 0 ? snoozeMinutes * 60 : 300
        let until = Date().addingTimeInterval(TimeInterval(snoozeSecs))
        appState.transition(to: .snoozed(until: until, count: newCount))

        // Start snooze mini-timer
        snoozeTimer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + .seconds(snoozeSecs))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.snoozeTimer = nil
            guard case .snoozed = self.appState.state else { return }
            let focusBlocks = UserDefaults.standard.bool(forKey: "respectFocusMode") && self.focusObserver.isFocusActive
            guard self.scheduleManager.shouldFire(), !focusBlocks else {
                log.notice("Snoozed checkpoint dropped: schedule or Focus no longer allows it")
                self.appState.transition(to: .idle)
                return
            }
            if self.holdsForCall {
                log.notice("Snoozed check-in held: on a call")
                self.appState.transition(to: .idle)
                self.checkInHeldForCall = true
                return
            }
            self.presentCheckpoint(session: session, snoozeCount: newCount)
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

    // MARK: - Settings Observation

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
                self?.objectiveTracker.heartbeat()
                self?.checkIdle()
            }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
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

    // MARK: - Calls (#1)

    private var holdsForCall: Bool {
        callDetector.isInCall && UserDefaults.standard.bool(forKey: "holdDuringCalls")
    }

    private func callChanged(inCall: Bool) {
        statusItemController?.updateDisplay()
        guard !inCall, checkInHeldForCall else { return }
        checkInHeldForCall = false
        // The held check-in shows now, quietly, if nothing else rules it out
        if appState.state == .idle {
            log.notice("Call ended: showing the held check-in")
            handleTimerFire(afterCall: true)
        }
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
        guard awayReasons.isEmpty, welcomeController == nil else { return nil }
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
        let interval = TimeInterval(UserDefaults.standard.integer(forKey: "checkpointInterval"))
        if checkpointTimer == nil {
            startTimer()
        } else {
            checkpointTimer?.restart(interval: interval > 0 ? interval : 2700)
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

    // MARK: - Dock Icon

    private func setDockIcon() {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size, flipped: false) { rect in
            // Orange gradient background
            let gradient = NSGradient(
                starting: NSColor(red: 1.0, green: 0.72, blue: 0.2, alpha: 1.0),
                ending: NSColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 1.0)
            )
            let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 16, dy: 16), xRadius: 96, yRadius: 96)
            gradient?.draw(in: bgPath, angle: -45)

            // White sun — center circle
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let sunRadius: CGFloat = 80
            let sunPath = NSBezierPath(ovalIn: NSRect(
                x: center.x - sunRadius, y: center.y - sunRadius,
                width: sunRadius * 2, height: sunRadius * 2
            ))
            NSColor.white.setFill()
            sunPath.fill()

            // Rays
            NSColor.white.setStroke()
            let rayLength: CGFloat = 50
            let rayGap: CGFloat = 30
            let rayStart = sunRadius + rayGap
            for i in 0..<8 {
                let angle = CGFloat(i) * .pi / 4
                let ray = NSBezierPath()
                ray.lineWidth = 28
                ray.lineCapStyle = .round
                ray.move(to: NSPoint(
                    x: center.x + cos(angle) * rayStart,
                    y: center.y + sin(angle) * rayStart
                ))
                ray.line(to: NSPoint(
                    x: center.x + cos(angle) * (rayStart + rayLength),
                    y: center.y + sin(angle) * (rayStart + rayLength)
                ))
                ray.stroke()
            }
            return true
        }
        NSApp.applicationIconImage = image
    }

    // MARK: - Dock Menu

    private func syncDockMenu() {}

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
            let interval = TimeInterval(UserDefaults.standard.integer(forKey: "checkpointInterval"))
            self?.checkpointTimer?.restart(interval: interval > 0 ? interval : 2700)
            self?.elapsedSince = Date()
            self?.objectiveTracker.endAway()  // the clock starts again
            self?.appState.transition(to: .idle)
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

    /// Manual check-in: an explicit request, so it skips the schedule and Focus gates.
    @objc func triggerNow() {
        switch appState.state {
        case .presenting, .triggered, .paused:
            log.notice("Manual check-in ignored: state=\(String(describing: self.appState.state), privacy: .public)")
            return
        default:
            break
        }
        guard awayReasons.isEmpty else {
            log.notice("Manual check-in ignored: user away")
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

// MARK: - UserDefaults KVO Extension

extension UserDefaults {
    @objc dynamic var currentObjective: String? {
        return string(forKey: "currentObjective")
    }

    @objc dynamic var currentIfThenPlan: String? {
        return string(forKey: "currentIfThenPlan")
    }

    @objc dynamic var checkpointInterval: Int {
        return integer(forKey: "checkpointInterval")
    }
}
