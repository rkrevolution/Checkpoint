import AppKit
import Carbon.HIToolbox
import os.log
import ServiceManagement

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "AppDelegate")

/// Launch wiring and menu actions only (#18). The work lives in focused types:
/// `CheckInScheduler` (when check-ins happen), `PresenceMonitor` (away, idle, calls, Focus),
/// `WindowRouter` (every window), `ObjectiveTracker` (what you're on and for how long),
/// `Diagnostics` and `AppSettings`.
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Services

    let settings = AppSettings()
    let appState = AppState()
    let questionBank = QuestionBank()
    let responseLog = ResponseLog()
    let customStore = CustomQuestionStore()
    let presence = PresenceMonitor()
    let objectiveTracker = ObjectiveTracker(
        defaults: DataLocation.defaults, sessionsURL: DataLocation.url("sessions.jsonl"))
    let parkedThoughts = ParkedThoughts(defaults: DataLocation.defaults, url: DataLocation.url("parked.jsonl"))
    lazy var scheduler = CheckInScheduler(
        appState: appState, settings: settings, scheduleManager: ScheduleManager(settings: settings),
        questionBank: questionBank, responseLog: responseLog, presence: presence,
        store: DataLocation.defaults)
    lazy var router = WindowRouter(tracker: objectiveTracker, parkedThoughts: parkedThoughts, responseLog: responseLog)
    lazy var commands = AppCommands(
        changeObjective: { [weak self] in self?.updateObjectiveFromMenu() },
        showHowItWorks: { [weak self] in self?.showHowItWorks() },
        diagnostics: { [weak self] in self?.diagnostics.rows() ?? [] }
    )
    private lazy var focusPill = FocusPillController(tracker: objectiveTracker) { [weak self] in
        self?.updateObjectiveFromMenu()
    }
    private var statusItemController: StatusItemController?
    private var pauseHotKey: GlobalHotKey?
    private var heartbeatTimer: Timer?
    /// Set once launch setup is done, so the stall check doesn't fire before the timer starts
    private var launchFinished = false

    /// Away this long brings up "Welcome back" to pick up (or change) the objective.
    private static let welcomeBackAfter: TimeInterval = 60 * 60

    private static var isUnitTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When hosting unit tests, don't start the app (it would touch real user data)
        guard !Self.isUnitTestHost else { return }
        log.notice("applicationDidFinishLaunching — loginItem=\(Diagnostics.loginItemText(SMAppService.mainApp.status), privacy: .public)")
        log.notice("\(AppInfo.displayString, privacy: .public)")
        log.notice("Check-ins \(ScreenCapturePrivacy.statusText(), privacy: .public)")
        #if DEBUG
        NSApp.dockTile.badgeLabel = "DEV"  // tell a Debug copy apart from the installed one
        observeDebugCommands()
        #endif

        Randomness.migrate()
        // Continue today's session, if any; none means the objective prompt appears below
        objectiveTracker.resume()
        questionBank.customStore = customStore

        wireCheckIns()
        wirePresence()
        focusPill.follow(appState: appState, isAway: { [presence] in presence.isAway })
        startHeartbeat()

        let statusItem = StatusItemController(appDelegate: self)
        statusItem.setup()
        statusItemController = statusItem
        // ⌃⌥⌘P pauses or resumes from any app (#15)
        pauseHotKey = GlobalHotKey(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey | cmdKey) { [weak self] in
            self?.togglePause()
        }

        log.notice("hasLaunchedBefore=\(FirstLaunch.isDone)")
        if !FirstLaunch.isDone {
            router.showWelcome { [weak self] in
                FirstLaunch.isDone = true
                self?.showDayStartPrompt()
            }
        } else if objectiveTracker.current == nil {
            // Only ask when there's no objective for today; otherwise just keep going (U1)
            showDayStartPrompt()
        } else {
            scheduler.start()
        }

        launchFinished = true
        statusItemController?.updateDisplay()
    }

    private func wireCheckIns() {
        scheduler.onPresent = { [weak self] session, snoozeCount, allowSnooze in
            guard let self else { return }
            self.router.showCard(
                session, checkInNumber: self.scheduler.day.count, allowSnooze: allowSnooze,
                onAnswered: { [weak self] in self?.scheduler.answered($0) },
                onSnoozed: { [weak self] in self?.scheduler.snoozed($0, snoozeCount: snoozeCount) })
        }
        scheduler.onEndOfActiveHours = { [weak self] in self?.router.showToday(headline: "End of active hours") }
        scheduler.onDismissCard = { [weak self] in self?.router.dismissCard() }
    }

    private func wirePresence() {
        presence.onAwayBegan = { [weak self] in self?.awayBegan() }
        presence.onAwayEnded = { [weak self] awayFor in self?.awayEnded(awayFor: awayFor) }
        presence.onIdleChanged = { [weak self] isIdle, time in
            if isIdle { self?.objectiveTracker.beginAway(at: time) } else { self?.objectiveTracker.endAway(at: time) }
        }
        presence.onCallChanged = { [weak self] inCall in
            self?.statusItemController?.updateDisplay()
            self?.scheduler.callChanged(inCall: inCall)  // hold check-ins during calls (#1)
        }
        presence.onFocusChanged = { [weak self] active in self?.scheduler.focusChanged(isActive: active) }
        presence.start()
    }

    /// Every 30 s: a new day (#51), the "last seen" time that lets the tracker exclude time the
    /// app wasn't running, and idle detection.
    private func startHeartbeat() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Before the heartbeat, which would move "last seen" past midnight
                if self.objectiveTracker.endIfFromEarlierDay() { self.newDayStarted() }
                self.objectiveTracker.heartbeat()
                self.presence.checkIdle(isPaused: self.appState.state == .paused)
            }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        objectiveTracker.heartbeat()
    }

    // MARK: - Flow between the parts

    /// Launch, Welcome done, or a new day: start check-ins right away (the prompt is optional and
    /// can end up buried behind other windows), then ask what today is about.
    private func showDayStartPrompt() {
        if !scheduler.isStarted { scheduler.start() }
        router.showDayStartPrompt()
    }

    /// The app ran past midnight with a session open (#51): yesterday's session has ended, so ask
    /// what today is about. Not while away or paused (Resume and a long absence bring up
    /// "Welcome back"); either way, until an objective is set the next card asks for one.
    private func newDayStarted() {
        scheduler.newDay()
        guard !presence.isAway, appState.state != .paused, !router.isPrompting else { return }
        showDayStartPrompt()
    }

    private func awayBegan() {
        objectiveTracker.beginAway()
        scheduler.awayBegan()
        focusPill.refresh()
    }

    private func awayEnded(awayFor: TimeInterval) {
        // While paused the clock stays stopped until Resume
        if appState.state != .paused {
            objectiveTracker.endAway()
            if awayFor >= Self.welcomeBackAfter, !router.isPrompting {
                log.notice("Back after \(Int(awayFor / 60)) min: welcome back")
                router.showObjectivePrompt(greeting: "Welcome back")
            }
        }
        focusPill.refresh()
        scheduler.awayEnded()
    }

    /// Pausing stops check-ins and the clock on the current objective; any open card closes (#49).
    @objc func pauseCheckpoints() {
        scheduler.pause()
        objectiveTracker.beginAway()
    }

    /// Resuming asks what you're on, then starts a fresh interval and the clock.
    @objc func resumeCheckpoints() {
        router.showObjectivePrompt(greeting: "Welcome back") { [weak self] in
            self?.scheduler.resume()
            self?.objectiveTracker.endAway()
        }
    }

    private func togglePause() {
        log.notice("Shortcut: \(self.appState.state == .paused ? "resume" : "pause")")
        appState.state == .paused ? resumeCheckpoints() : pauseCheckpoints()
    }

    // MARK: - Status (menu bar, Diagnostics)

    /// Why check-ins have stopped when they shouldn't have, or nil if all is well (#25).
    var stallReason: String? {
        guard launchFinished, !router.isShowingWelcome else { return nil }
        return scheduler.stallReason(isCardVisible: router.isCardVisible)
    }

    func logStall(_ reason: String) {
        log.error("Check-ins stalled: \(reason, privacy: .public) state=\(String(describing: self.appState.state), privacy: .public)")
    }

    private var diagnostics: Diagnostics {
        Diagnostics(appState: appState, scheduler: scheduler, presence: presence,
                    settings: settings, stallReason: stallReason)
    }

    // MARK: - Menu actions

    @objc func triggerNow() { scheduler.checkInNow() }
    @objc func pauseFromMenu() { pauseCheckpoints() }
    @objc func resumeFromMenu() { resumeCheckpoints() }
    @objc func updateObjectiveFromMenu() { router.showObjectivePrompt() }
    @objc func showTodayFromMenu() { router.showToday() }
    @objc func showHowItWorks() { router.showHowItWorks() }
    @objc func parkThoughtFromMenu() { router.parkThought() }
    @objc func openPreferences() { router.openSettings() }
    @objc func toggleFocusPill() { settings.showFocusPill.toggle() }

    @objc func markParkedThoughtDone(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        parkedThoughts.markDone(id)
    }

    /// Menu action shown with the stall warning: clears whatever is stuck and starts fresh.
    @objc func restartCheckIns() {
        scheduler.restart()
        statusItemController?.updateDisplay()
    }

    // MARK: - Dock

    /// Clicking the Dock icon (or opening the app again from Finder or Spotlight) opens
    /// Settings when nothing else is showing: it's the app's main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        log.notice("Reopen: opening Settings")
        openPreferences()
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        if appState.state == .paused {
            menu.addItem(withTitle: "Resume Checkpoints", action: #selector(resumeCheckpoints), keyEquivalent: "")
        } else {
            menu.addItem(withTitle: "Pause Checkpoints", action: #selector(pauseCheckpoints), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openPreferences), keyEquivalent: ",")
        return menu
    }
}
