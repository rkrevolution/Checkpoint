import Foundation

/// Version details for display (menu bar, Settings, logs).
enum AppInfo {
    nonisolated static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    nonisolated static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// Window title with the app and version, e.g. "Today — Checkpoint v1.0" ("… v1.0 Debug" in Debug builds).
    nonisolated static func windowTitle(_ name: String) -> String {
        #if DEBUG
        return "\(name) — Checkpoint v\(version) Debug"
        #else
        return "\(name) — Checkpoint v\(version)"
        #endif
    }

    /// e.g. "Checkpoint 1.0 (124)", with " · Debug" for Debug builds.
    nonisolated static var displayString: String {
        #if DEBUG
        return "Checkpoint \(version) (\(build)) · Debug"
        #else
        return "Checkpoint \(version) (\(build))"
        #endif
    }
}
