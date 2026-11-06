import Foundation
import ServiceManagement

/// What the app is doing right now, as label/value rows for Settings › Diagnostics (#18).
/// Reads the scheduler and presence; never changes anything.
@MainActor
struct Diagnostics {
    let appState: AppState
    let scheduler: CheckInScheduler
    let presence: PresenceMonitor
    let settings: AppSettings
    let stallReason: String?

    func rows() -> [(label: String, value: String)] {
        let interval = settings.checkInInterval
        return [
            ("Next check-in", scheduler.nextCheckInDescription),
            ("Last check-in", scheduler.day.lastCheckIn?.formatted(date: .omitted, time: .standard) ?? "none since launch"),
            ("State", String(describing: appState.state)),
            ("Stall check", stallReason ?? "OK"),
            ("Away", presence.isAway ? presence.awayReasons.map(\.rawValue).sorted().joined(separator: ", ") : "no"),
            ("Idle (5+ min)", presence.isIdle ? "yes" : "no"),
            ("On a call", presence.isOnCall ? "yes" : "no"),
            ("Focus detected", (presence.isFocusActive ? "yes" : "no") + (settings.respectFocus ? "" : " (not respected)")),
            ("Start at Login", Self.loginItemText(SMAppService.mainApp.status)),
            ("Screen capture", "Check-ins " + ScreenCapturePrivacy.statusText()),
            ("Interval", "every \(DurationText.long(interval)), randomness \(settings.randomness.label(for: interval))"),
            ("Version", AppInfo.displayString),
            ("Data folder", JSONLinesFile<ParkedThought>.appSupportURL("").path),
        ]
    }

    nonisolated static func loginItemText(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "on"
        case .requiresApproval: return "needs approval in System Settings › General › Login Items"
        case .notRegistered: return "off"
        case .notFound: return "not found (unsigned or moved build?)"
        @unknown default: return "unknown"
        }
    }
}
