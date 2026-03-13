import AppKit
import Combine
import os.log
import ServiceManagement

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "AppDelegate")

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Owned Objects
    let appState = AppState()
    let scheduleManager = ScheduleManager()
    let questionBank = QuestionBank()
    let notificationMgr = NotificationManager()
    let focusObserver = FocusModeObserver()
    let responseLog = ResponseLog()
    let customStore = CustomQuestionStore()
    var checkpointTimer: CheckpointTimer?
    private var snoozeTimer: DispatchSourceTimer?
    private var windowController: CheckpointWindowController?
    private var welcomeController: WelcomeWindowController?
    private var objectiveController: ObjectivePromptController?
    private var statusItemController: StatusItemController?
    private var daySummaryController: DaySummaryController?
    private let transitionToast = TransitionToast()
    private var cancellables = Set<AnyCancellable>()
    private var todayCheckpointCount = 0
    private var lastCheckpointDate: Date?
    private var todayObjectives: [String] = []
    private var hasShownDaySummary = false

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        ])

        // 1. Give QuestionBank access to custom questions
        questionBank.customStore = customStore

        // 2. Wire Focus observer → AppState (always observe; setting checked at fire time)
        focusObserver.onFocusChanged = { [weak self] isActive in
            guard let self else { return }
            if isActive {
                self.appState.transition(to: .focusModeActive)
            } else if self.appState.state == .focusModeActive {
                self.appState.transition(to: .idle)
            }
        }
        focusObserver.startObserving()

        // 3. Set dock icon programmatically (sun)
        setDockIcon()

        // 4. Request notification permission
        notificationMgr.requestPermission { _ in }

        // 5. Setup menu bar status item (running indicator + countdown)
        let sic = StatusItemController(appDelegate: self)
        sic.setup()
        statusItemController = sic

        // 6. Observe sleep/wake to pause and resume the timer
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)

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
            showObjectivePrompt()
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
        let oc = ObjectivePromptController { [weak self] in
            self?.objectiveController = nil
            log.notice("Objective prompt dismissed, starting timer")
            self?.startTimer()
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
    }

    // MARK: - Sleep / Wake

    @objc private func handleSleep(_ notification: Notification) {
        log.notice("━━━ SYSTEM SLEEP ━━━")
        checkpointTimer?.stop()
        snoozeTimer?.cancel()
        snoozeTimer = nil
    }

    @objc private func handleWake(_ notification: Notification) {
        log.notice("━━━ SYSTEM WAKE ━━━")
        log.notice("  State on wake: \(String(describing: self.appState.state))")

        // If user had manually paused, respect that
        if appState.state == .paused {
            log.notice("  User was paused before sleep, staying paused")
            return
        }

        // Dismiss any stale checkpoint window
        if appState.state == .presenting || appState.state == .triggered {
            log.notice("  Dismissing stale checkpoint window")
            windowController?.close()
            windowController = nil
        }

        // Cancel any stale snooze
        snoozeTimer?.cancel()
        snoozeTimer = nil

        // Restart fresh
        appState.transition(to: .idle)
        let interval = TimeInterval(UserDefaults.standard.integer(forKey: "checkpointInterval"))
        let effectiveInterval = interval > 0 ? interval : 2700
        checkpointTimer?.restart(interval: effectiveInterval)
        log.notice("  Timer restarted with interval \(Int(effectiveInterval))s")
    }

    // MARK: - Timer Fire

    private func resetDayCountersIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if let lastDate = lastCheckpointDate, Calendar.current.startOfDay(for: lastDate) != today {
            todayCheckpointCount = 0
            todayObjectives = []
            hasShownDaySummary = false
        }
    }

    private func handleTimerFire() {
        log.notice("handleTimerFire: currentState=\(String(describing: self.appState.state))")

        // Reset daily counters on day boundary regardless of whether checkpoint fires
        resetDayCountersIfNeeded()

        // Recover from outsideHours when hours become active again
        if appState.state == .outsideHours, scheduleManager.isWithinActiveHours() {
            log.notice("Recovering from outsideHours → idle")
            appState.transition(to: .idle)
            hasShownDaySummary = false
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

        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        log.notice("━━━ CHECKPOINT FIRING ━━━")
        log.notice("  Time: \(formatter.string(from: Date()))")
        log.notice("  All gates passed ✓")
        appState.transition(to: .triggered)

        let interval = UserDefaults.standard.integer(forKey: "checkpointInterval")
        let count = UserDefaults.standard.integer(forKey: "questionsPerCheckpoint")
        let questions = questionBank.selectQuestions(
            count: count > 0 ? count : 1,
            recentCategoryIds: appState.recentCategoryIds
        )

        let actualElapsed: Int
        if let last = lastCheckpointDate {
            actualElapsed = Int(Date().timeIntervalSince(last))
        } else {
            actualElapsed = interval > 0 ? interval : 2700
        }

        let session = CheckpointSession(
            id: UUID(),
            timestamp: Date(),
            intervalSeconds: actualElapsed,
            questionsShown: questions,
            responses: questions.map { QuestionResponse(questionId: $0.id, text: "") },
            outcome: .completed
        )

        appState.recordShownCategories(questions.map(\.categoryId))

        // Track daily checkpoint count and objectives
        todayCheckpointCount += 1
        lastCheckpointDate = Date()

        let currentObj = UserDefaults.standard.string(forKey: "currentObjective") ?? ""
        if !currentObj.isEmpty, !todayObjectives.contains(currentObj) {
            todayObjectives.append(currentObj)
        }

        // Play sound if enabled
        if UserDefaults.standard.bool(forKey: "playSoundOnCheckpoint") {
            let soundName = UserDefaults.standard.string(forKey: "soundName") ?? "Glass"
            NSSound(named: NSSound.Name(soundName))?.play()
        }

        log.notice("Presenting checkpoint: \(questions.count) questions, objective='\(currentObj)'")
        presentCheckpoint(session: session, snoozeCount: 0)
    }

    private func presentCheckpoint(session: CheckpointSession, snoozeCount: Int) {
        log.notice("presentCheckpoint: snoozeCount=\(snoozeCount)")
        appState.transition(to: .presenting)

        let interval = UserDefaults.standard.integer(forKey: "checkpointInterval")
        let mins = max(1, interval / 60)
        let estimate = "~\(mins) min"

        let objective = UserDefaults.standard.string(forKey: "currentObjective") ?? ""

        let wc = CheckpointWindowController(
            session: session,
            currentObjective: objective,
            nextCheckpointEstimate: estimate,
            checkpointNumber: todayCheckpointCount,
            onDone: { [weak self] completed, updatedObjective in
                let formatter = DateFormatter()
                formatter.timeStyle = .medium
                log.notice("━━━ CHECKPOINT COMPLETED ━━━")
                log.notice("  User tapped 'Got it' at \(formatter.string(from: Date()))")
                log.notice("  Objective updated: \(updatedObjective != nil ? "yes" : "no")")
                self?.windowController = nil
                // Save updated objective if user changed it, show transition toast
                if let updated = updatedObjective, !updated.isEmpty {
                    let old = UserDefaults.standard.string(forKey: "currentObjective") ?? ""
                    UserDefaults.standard.set(updated, forKey: "currentObjective")
                    if old != updated {
                        self?.transitionToast.show(from: old, to: updated)
                    }
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
            var snoozed = session
            snoozed.outcome = .snoozed
            try? responseLog.append(snoozed)
        }

        // Check if max snoozes reached
        if maxSnoozes > 0, newCount >= maxSnoozes {
            let action = UserDefaults.standard.string(forKey: "afterMaxSnoozeAction") ?? "autoDismiss"
            if action == "autoDismiss" {
                appState.transition(to: .idle)
                return
            } else {
                // Force open modal
                presentCheckpoint(session: session, snoozeCount: newCount)
                return
            }
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
            self.presentCheckpoint(session: session, snoozeCount: newCount)
        }
        source.resume()
        snoozeTimer = source
    }

    // MARK: - Day Summary

    private func showDaySummaryIfNeeded() {
        guard !hasShownDaySummary, todayCheckpointCount > 0 else { return }
        hasShownDaySummary = true

        let controller = DaySummaryController(
            checkpointCount: todayCheckpointCount,
            objectives: todayObjectives
        )
        daySummaryController = controller
        controller.show()
    }

    // MARK: - Settings Observation

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

        let nextItem = NSMenuItem(title: nextCheckpointLabel(), action: nil, keyEquivalent: "")
        nextItem.isEnabled = false
        menu.addItem(nextItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")

        return menu
    }

    @objc private func pauseCheckpoints() {
        checkpointTimer?.stop()
        snoozeTimer?.cancel()
        snoozeTimer = nil
        appState.transition(to: .paused)
    }

    @objc private func resumeCheckpoints() {
        // Re-prompt for objective on resume, then restart timer
        let oc = ObjectivePromptController { [weak self] in
            self?.objectiveController = nil
            let interval = TimeInterval(UserDefaults.standard.integer(forKey: "checkpointInterval"))
            self?.checkpointTimer?.restart(interval: interval > 0 ? interval : 2700)
            self?.appState.transition(to: .idle)
        }
        objectiveController = oc
        oc.show()
    }

    @objc func openPreferences() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    // Called from StatusItemController menu
    @objc func pauseFromMenu() { pauseCheckpoints() }
    @objc func resumeFromMenu() { resumeCheckpoints() }

    @objc func updateObjectiveFromMenu() {
        let oldObjective = UserDefaults.standard.string(forKey: "currentObjective") ?? ""
        let oc = ObjectivePromptController { [weak self] in
            self?.objectiveController = nil
            let newObjective = UserDefaults.standard.string(forKey: "currentObjective") ?? ""
            if oldObjective != newObjective {
                self?.transitionToast.show(from: oldObjective, to: newObjective)
            }
        }
        objectiveController = oc
        oc.show()
    }

    @objc func triggerNow() {
        // Force a checkpoint immediately regardless of timer
        guard appState.state == .idle || appState.state == .outsideHours else { return }
        appState.transition(to: .idle)
        handleTimerFire()
    }

    private func nextCheckpointLabel() -> String {
        guard let next = checkpointTimer?.nextFireDate else { return "Checkpoints paused" }
        let mins = max(1, Int(next.timeIntervalSinceNow / 60))
        return "Next check-in: ~\(mins) min"
    }
}

// MARK: - UserDefaults KVO Extension

extension UserDefaults {
    @objc dynamic var checkpointInterval: Int {
        return integer(forKey: "checkpointInterval")
    }
}
