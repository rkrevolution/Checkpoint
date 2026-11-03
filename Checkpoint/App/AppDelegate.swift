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
    /// Start of the stretch the checkpoint card reports as "N minutes have passed".
    /// Reset when the timer (re)starts, on return from away, and when a checkpoint is acknowledged.
    private var elapsedSince: Date?
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
        // Start right away: the prompt is optional and can end up buried behind other windows
        if checkpointTimer == nil {
            startTimer()
        }
        let oc = ObjectivePromptController { [weak self] in
            self?.objectiveController = nil
            log.notice("Objective prompt dismissed")
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
        log.notice("━━━ AWAY: \(reason.rawValue, privacy: .public) (reasons=\(self.awayReasons.map(\.rawValue), privacy: .public)) ━━━")
        guard !wasAway else { return }

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
            todayObjectives = []
            hasShownDaySummary = false
        }
    }

    private func handleTimerFire() {
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

        log.notice("  All gates passed ✓")
        fireCheckpoint()
    }

    /// Builds and presents a checkpoint. Callers are responsible for the schedule/Focus gates.
    private func fireCheckpoint() {
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
        let mins = max(1, interval / 60)
        let estimate = "~\(mins) min"

        let objective = UserDefaults.standard.string(forKey: "currentObjective") ?? ""
        let maxSnoozes = UserDefaults.standard.integer(forKey: "maxSnoozesPerCheckpoint")

        let wc = CheckpointWindowController(
            session: session,
            currentObjective: objective,
            nextCheckpointEstimate: estimate,
            checkpointNumber: todayCheckpointCount,
            allowSnooze: maxSnoozes == 0 || snoozeCount < maxSnoozes,
            onDone: { [weak self] completed, updatedObjective in
                let formatter = DateFormatter()
                formatter.timeStyle = .medium
                log.notice("━━━ CHECKPOINT COMPLETED ━━━")
                log.notice("  User tapped 'Got it' at \(formatter.string(from: Date()))")
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
            self?.elapsedSince = Date()
            self?.appState.transition(to: .idle)
        }
        objectiveController = oc
        oc.show()
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

    private func nextCheckpointLabel() -> String {
        guard let next = checkpointTimer?.nextFireDate else { return "Checkpoints paused" }
        let mins = max(1, Int(next.timeIntervalSinceNow / 60))
        return "Next check-in: ~\(mins) min"
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
    @objc dynamic var checkpointInterval: Int {
        return integer(forKey: "checkpointInterval")
    }
}
