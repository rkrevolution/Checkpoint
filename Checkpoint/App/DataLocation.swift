import Foundation

/// Where the app keeps the user's data, in one place: tracker state and history files in
/// Application Support, or a throwaway folder for the end-to-end test.
enum DataLocation {

    /// Debug builds launched with `-e2eDataDir <path>` (scripts/e2e.sh) keep tracker and parked
    /// data in a throwaway place, so tests never touch the user's real sessions.
    private static let testDataDir: URL? = {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "e2eDataDir") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return nil
    }()

    /// Small state that belongs with the data (open session, next check-in due, parked done).
    static let defaults: UserDefaults = {
        guard testDataDir != nil else { return .standard }
        let suite = "RkRev.Checkpoint.e2e"
        guard let defaults = UserDefaults(suiteName: suite) else { return .standard }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }()

    static func url(_ name: String) -> URL {
        testDataDir?.appendingPathComponent(name) ?? JSONLinesFile<ParkedThought>.appSupportURL(name)
    }
}

/// Whether Welcome has been completed. Stored in the standard preferences (where it always was),
/// so the e2e test can set it with `-hasLaunchedBefore YES`.
enum FirstLaunch {
    private static let key = "hasLaunchedBefore"

    static var isDone: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    #if DEBUG
    static func reset() { UserDefaults.standard.removeObject(forKey: key) }
    #endif
}
