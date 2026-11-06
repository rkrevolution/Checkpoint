import AppKit

/// Whether Checkpoint's windows (the check-in card, its dimming overlays and the focus strip)
/// are kept out of screen capture. macOS uses one mechanism for screen sharing, recordings and
/// screenshots, so hiding from one hides from all: on by default (your objective and goals stay
/// private on calls), off when you need a screenshot.
/// Override for one run: `scripts/run.sh -hideFromScreenCapture NO`.
enum ScreenCapturePrivacy {
    nonisolated static let key = "hideFromScreenCapture"
    nonisolated static let defaultValue = true

    nonisolated static func isHidden(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
    }

    nonisolated static func sharingType(hidden: Bool) -> NSWindow.SharingType {
        hidden ? .none : .readOnly
    }

    /// Applies the current setting to a window. Call when creating it, and again for long-lived
    /// windows when the setting changes.
    static func apply(to window: NSWindow, defaults: UserDefaults = .standard) {
        window.sharingType = sharingType(hidden: isHidden(defaults))
    }

    /// For Diagnostics and the log.
    nonisolated static func statusText(_ defaults: UserDefaults = .standard) -> String {
        isHidden(defaults)
            ? "hidden from screen sharing and screenshots"
            : "visible to screen sharing and screenshots"
    }
}
