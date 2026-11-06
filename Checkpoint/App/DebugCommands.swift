#if DEBUG
import AppKit
import os.log

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "DebugCommands")

/// The Debug menu and the commands `scripts/e2e.sh` sends. Debug builds only; everything goes
/// through the same public paths as real events, so the gates apply.
extension AppDelegate {

    var debugScreensaverActive: Bool { presence.awayReasons.contains(.screensaver) }
    var debugScreenLocked: Bool { presence.awayReasons.contains(.screenLocked) }

    /// Goes through the normal manual path (away and pause still apply).
    @objc func debugCheckInSoon() {
        log.notice("DEBUG: check-in in 10s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.triggerNow()
        }
    }

    @objc func debugToggleScreensaver() {
        debugScreensaverActive ? presence.endAway(.screensaver) : presence.beginAway(.screensaver)
    }

    @objc func debugToggleScreenLock() {
        debugScreenLocked ? presence.endAway(.screenLocked) : presence.beginAway(.screenLocked)
    }

    @objc func debugToggleFocus() {
        presence.debugSetFocus(!presence.isFocusActive)
    }

    @objc func debugResetFirstLaunch() {
        FirstLaunch.reset()
        log.notice("DEBUG: first-launch flag cleared; Welcome shows on next launch")
    }

    /// Commands a test script can send: `com.rkrev.checkpoint.debug.<command>` as a distributed
    /// notification (see scripts/e2e.sh).
    private static let debugCommands: [String: (AppDelegate) -> Void] = [
        "checkInNow": { $0.triggerNow() },
        "acknowledge": { $0.router.debugAcknowledge() },
        "snooze": { $0.router.debugSnooze() },
        "pause": { $0.pauseCheckpoints() },
        "focusOn": { $0.presence.debugSetFocus(true) },
        "focusOff": { $0.presence.debugSetFocus(false) },
        "screensaverStart": { $0.presence.beginAway(.screensaver) },
        "screensaverStop": { $0.presence.endAway(.screensaver) },
        "lockStart": { $0.presence.beginAway(.screenLocked) },
        "lockStop": { $0.presence.endAway(.screenLocked) },
        "callStart": { $0.presence.debugSetCall(true) },
        "callStop": { $0.presence.debugSetCall(false) },
        "timerFire": { $0.scheduler.timerFired() },
    ]

    func observeDebugCommands() {
        for (command, run) in Self.debugCommands {
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.rkrev.checkpoint.debug.\(command)"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    log.notice("DEBUG command: \(command, privacy: .public)")
                    run(self)
                }
            }
        }
    }
}
#endif
