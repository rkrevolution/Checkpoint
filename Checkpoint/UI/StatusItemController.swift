import AppKit
import Combine

/// Menu bar item: shows time on the current objective (or the next check-in countdown,
/// if the user prefers), a warning if check-ins have stopped, and the app's menu.
///
/// The title refreshes on state changes and on a slow timer, and the menu is built only
/// when it opens, so the app stays idle between check-ins.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private weak var appDelegate: AppDelegate?
    private var lastTitle = ""
    private var lastSymbol = ""
    private var loggedStallReason: String?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        #if DEBUG
        // Tell a Debug copy apart from an installed release copy at a glance
        item.button?.contentTintColor = .systemOrange
        #endif
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        appDelegate?.appState.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateDisplay() }
            .store(in: &cancellables)
        UserDefaults.standard.publisher(for: \.currentObjective)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateDisplay() }
            .store(in: &cancellables)

        updateDisplay()
        // Minute-resolution display: a slow, tolerant timer keeps wake-ups rare
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDisplay() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Title

    func updateDisplay() {
        guard let button = statusItem?.button, let appDelegate else { return }
        let (title, symbol, description) = titleAndSymbol(appDelegate)

        if let reason = appDelegate.stallReason, reason != loggedStallReason {
            appDelegate.logStall(reason)
        }
        loggedStallReason = appDelegate.stallReason

        // Only touch the button when something visible changed
        if title != lastTitle {
            button.title = title
            lastTitle = title
        }
        if symbol != lastSymbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
            lastSymbol = symbol
        }
        button.toolTip = tooltip(appDelegate)
    }

    private func titleAndSymbol(_ app: AppDelegate) -> (String, String, String) {
        if app.stallReason != nil {
            return (" Check-ins stopped", "exclamationmark.triangle.fill", "Check-ins stopped")
        }
        switch app.appState.state {
        case .idle, .triggered:
            return (" " + idleTitle(app), "sun.max.fill", "Checkpoint")
        case .presenting:
            return (" Check-in", "bubble.left.fill", "Checkpoint active")
        case .snoozed(let until, _):
            return (" " + DurationText.short(max(60, until.timeIntervalSinceNow)), "clock.arrow.circlepath", "Snoozed")
        case .paused:
            return (" Paused", "pause.circle", "Paused")
        case .outsideHours:
            return (" Off hours", "moon.fill", "Outside active hours")
        case .focusModeActive:
            return (" Focus", "moon.fill", "Focus mode")
        }
    }

    private func idleTitle(_ app: AppDelegate) -> String {
        let showCountdown = AppSettings().menuBarDisplay == .countdown
        if !showCountdown, let active = app.objectiveTracker.activeSeconds() {
            return DurationText.short(active)
        }
        if showCountdown, let next = app.checkpointTimer?.nextFireDate {
            return DurationText.short(max(60, next.timeIntervalSinceNow))
        }
        return ""
    }

    private func tooltip(_ app: AppDelegate) -> String {
        guard let session = app.objectiveTracker.current else { return "Checkpoint" }
        return "On \(session.objective) for \(DurationText.long(session.activeSeconds(at: Date()))) (not counting time away or idle)"
    }

    // MARK: - Menu (built when opened)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let app = appDelegate else { return }
        let state = app.appState.state

        if let reason = app.stallReason {
            menu.addItem(disabled("⚠ Check-ins stopped: \(reason)"))
            let restart = action("Restart Check-ins", #selector(AppDelegate.restartCheckIns), app)
            restart.toolTip = "Clears whatever is stuck and starts a fresh interval"
            menu.addItem(restart)
            menu.addItem(.separator())
        }

        let goals = AppSettings().goals
        if !goals.isEmpty {
            menu.addItem(disabled("Goals"))
            for goal in goals {
                menu.addItem(disabled("  ◎ \(goal)"))
            }
            menu.addItem(.separator())
        }

        let today = action("Today\u{2026}", #selector(AppDelegate.showTodayFromMenu), app)
        today.keyEquivalent = "t"
        today.toolTip = "Time per objective, estimates vs actual, check-in answers and parked thoughts"
        menu.addItem(today)
        menu.addItem(.separator())

        // What you're working on, and for how long
        if let session = app.objectiveTracker.current {
            menu.addItem(disabled("On: \(session.objective)"))
            menu.addItem(disabled(session.progressText(at: Date())))
            if let plan = session.ifThenPlan {
                menu.addItem(disabled("If I drift: \(plan)"))
            }
        } else {
            menu.addItem(disabled("No objective set"))
        }
        // "Set" when nothing is being tracked (skipped, or a new day), so the way back in is obvious
        let objectiveTitle = app.objectiveTracker.current == nil ? "Set Objective\u{2026}" : "Change Objective\u{2026}"
        menu.addItem(action(objectiveTitle, #selector(AppDelegate.updateObjectiveFromMenu), app))
        let showFocus = action("Show Focus", #selector(AppDelegate.toggleFocusPill), app)
        showFocus.state = AppSettings().showFocusPill ? .on : .off
        showFocus.toolTip = "A small strip at the top of the screen with your objective and time on it"
        menu.addItem(showFocus)
        let park = action("Park a Thought\u{2026}", #selector(AppDelegate.parkThoughtFromMenu), app)
        park.toolTip = "Write down a distraction to deal with later, then get back to work"
        menu.addItem(park)
        let open = app.parkedThoughts.open
        if !open.isEmpty {
            let submenu = NSMenu()
            submenu.addItem(disabled("Click to mark done"))
            for thought in open.suffix(15) {
                let item = action(thought.text, #selector(AppDelegate.markParkedThoughtDone(_:)), app)
                item.representedObject = thought.id
                submenu.addItem(item)
            }
            let parked = NSMenuItem(title: "Parked (\(open.count))", action: nil, keyEquivalent: "")
            parked.toolTip = "Things you parked for later. Click one to mark it done."
            parked.submenu = submenu
            menu.addItem(parked)
        }
        menu.addItem(.separator())

        // Check-in status
        // No "next check-in" time: unpredictable timing is the point
        menu.addItem(disabled(stateLabel(state)))
        if app.checkInHeldForCall {
            menu.addItem(disabled("On a call: your check-in will show when it ends"))
        } else if app.callDetector.isInCall {
            menu.addItem(disabled("On a call: check-ins wait until it ends"))
        }
        if let last = app.lastCheckInDate {
            menu.addItem(disabled("Last check-in: \(last.formatted(date: .omitted, time: .shortened))"))
        }
        switch state {
        case .paused, .presenting, .triggered:
            break
        default:
            menu.addItem(action("Check In Now", #selector(AppDelegate.triggerNow), app))
        }
        // Shows the global ⌃⌥⌘P shortcut (#15)
        let pause = state == .paused
            ? action("Resume Checkpoints", #selector(AppDelegate.resumeFromMenu), app)
            : action("Pause Checkpoints", #selector(AppDelegate.pauseFromMenu), app)
        pause.keyEquivalent = "p"
        pause.keyEquivalentModifierMask = [.control, .option, .command]
        menu.addItem(pause)
        menu.addItem(.separator())

        menu.addItem(action("How Checkpoint Works\u{2026}", #selector(AppDelegate.showHowItWorks), app))
        let prefs = action("Settings…", #selector(AppDelegate.openPreferences), app)
        prefs.keyEquivalent = ","
        menu.addItem(prefs)

        #if DEBUG
        menu.addItem(.separator())
        menu.addItem(buildDebugMenuItem(app))
        #endif

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Checkpoint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.addItem(disabled(AppInfo.displayString))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, _ target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = target
        return item
    }

    #if DEBUG
    private func buildDebugMenuItem(_ appDelegate: AppDelegate) -> NSMenuItem {
        let submenu = NSMenu()
        let items: [(String, Selector, Bool)] = [
            ("Check In in 10 Seconds", #selector(AppDelegate.debugCheckInSoon), false),
            ("Simulate Screensaver", #selector(AppDelegate.debugToggleScreensaver), appDelegate.debugScreensaverActive),
            ("Simulate Screen Lock", #selector(AppDelegate.debugToggleScreenLock), appDelegate.debugScreenLocked),
            ("Simulate Focus", #selector(AppDelegate.debugToggleFocus), appDelegate.focusObserver.isFocusActive),
            ("Reset First Launch", #selector(AppDelegate.debugResetFirstLaunch), false),
        ]
        submenu.addItem(disabled("Next check-in: \(appDelegate.nextCheckInDescription)"))
        submenu.addItem(.separator())
        for (title, selector, isOn) in items {
            let item = action(title, selector, appDelegate)
            item.state = isOn ? .on : .off
            submenu.addItem(item)
        }
        let debug = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        debug.submenu = submenu
        return debug
    }
    #endif

    private func stateLabel(_ state: CheckpointState) -> String {
        switch state {
        case .idle: return "Check-ins running"
        case .triggered, .presenting: return "Checkpoint active"
        case .snoozed: return "Snoozed"
        case .paused: return "Paused"
        case .outsideHours: return "Outside active hours"
        case .focusModeActive: return "Focus mode active"
        }
    }
}
