import AppKit
import Combine

@MainActor
final class StatusItemController {

    private var statusItem: NSStatusItem?
    private var updateTimer: Timer?
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Checkpoint")
        item.button?.imagePosition = .imageLeading
        statusItem = item
        updateDisplay()
        startUpdateTimer()
    }

    func updateDisplay() {
        guard let button = statusItem?.button, let appDelegate else { return }

        switch appDelegate.appState.state {
        case .idle:
            if let next = appDelegate.checkpointTimer?.nextFireDate {
                let remaining = max(0, Int(next.timeIntervalSinceNow))
                let mins = remaining / 60
                let secs = remaining % 60
                if mins > 0 {
                    button.title = " \(mins)m"
                } else {
                    button.title = " \(secs)s"
                }
            } else {
                button.title = ""
            }
            button.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Checkpoint")

        case .presenting:
            button.title = " Active"
            button.image = NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: "Checkpoint active")

        case .snoozed(let until, _):
            let remaining = max(0, Int(until.timeIntervalSinceNow))
            let mins = remaining / 60
            let secs = remaining % 60
            if mins > 0 {
                button.title = " \(mins)m"
            } else {
                button.title = " \(secs)s"
            }
            button.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Snoozed")

        case .paused:
            button.title = " Paused"
            button.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Paused")

        case .outsideHours:
            button.title = " Off hours"
            button.image = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "Outside hours")

        case .focusModeActive:
            button.title = " Focus"
            button.image = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "Focus mode")

        case .triggered:
            button.title = ""
            button.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Checkpoint")
        }

        // Show objective as tooltip
        let objective = UserDefaults.standard.string(forKey: "currentObjective") ?? ""
        button.toolTip = objective.isEmpty ? "Checkpoint" : objective

        // Rebuild menu
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        guard let appDelegate else { return menu }

        // State-specific action
        switch appDelegate.appState.state {
        case .paused:
            let resume = NSMenuItem(title: "Resume Checkpoints", action: #selector(AppDelegate.resumeFromMenu), keyEquivalent: "")
            resume.target = appDelegate
            menu.addItem(resume)
        default:
            let pause = NSMenuItem(title: "Pause Checkpoints", action: #selector(AppDelegate.pauseFromMenu), keyEquivalent: "")
            pause.target = appDelegate
            menu.addItem(pause)
        }

        menu.addItem(NSMenuItem.separator())

        // Next checkpoint info
        if let next = appDelegate.checkpointTimer?.nextFireDate, appDelegate.appState.state == .idle {
            let mins = max(1, Int(next.timeIntervalSinceNow / 60))
            let info = NSMenuItem(title: "Next check-in: ~\(mins) min", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        } else {
            let info = NSMenuItem(title: stateLabel(appDelegate.appState.state), action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }

        menu.addItem(NSMenuItem.separator())

        // Current objective (show it, make it tappable to edit)
        let objective = UserDefaults.standard.string(forKey: "currentObjective") ?? ""
        if !objective.isEmpty {
            let objItem = NSMenuItem(title: "Working on: \(objective)", action: nil, keyEquivalent: "")
            objItem.isEnabled = false
            menu.addItem(objItem)
        }

        let updateObj = NSMenuItem(title: "Update Objective\u{2026}", action: #selector(AppDelegate.updateObjectiveFromMenu), keyEquivalent: "")
        updateObj.target = appDelegate
        menu.addItem(updateObj)

        menu.addItem(NSMenuItem.separator())

        // Trigger now (not while paused or while a checkpoint is already up)
        switch appDelegate.appState.state {
        case .paused, .presenting, .triggered:
            break
        default:
            let triggerNow = NSMenuItem(title: "Check In Now", action: #selector(AppDelegate.triggerNow), keyEquivalent: "")
            triggerNow.target = appDelegate
            menu.addItem(triggerNow)
            menu.addItem(NSMenuItem.separator())
        }

        let prefs = NSMenuItem(title: "Preferences…", action: #selector(AppDelegate.openPreferences), keyEquivalent: ",")
        prefs.target = appDelegate
        menu.addItem(prefs)

        #if DEBUG
        menu.addItem(NSMenuItem.separator())
        menu.addItem(buildDebugMenuItem(appDelegate))
        #endif

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit Checkpoint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        let version = NSMenuItem(title: AppInfo.displayString, action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        return menu
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
        for (title, action, isOn) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = appDelegate
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
        case .idle: return "Running"
        case .triggered, .presenting: return "Checkpoint active"
        case .snoozed: return "Snoozed"
        case .paused: return "Paused"
        case .outsideHours: return "Outside active hours"
        case .focusModeActive: return "Focus mode active"
        }
    }

    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDisplay()
            }
        }
    }

    func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
}
