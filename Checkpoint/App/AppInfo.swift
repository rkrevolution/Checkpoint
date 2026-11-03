import Foundation

/// Version details for display (menu bar, Settings, logs).
enum AppInfo {
    nonisolated static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    nonisolated static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
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
