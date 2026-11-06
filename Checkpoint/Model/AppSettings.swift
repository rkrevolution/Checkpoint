import Foundation

/// The user's preferences, typed: the only place their keys and defaults are written down (#16).
///
/// Code reads and writes settings through this type; SwiftUI views bind with
/// `@AppStorage(AppSettings.Key.x.rawValue) var x = AppSettings.Default.x`, so the key and the
/// default still have one definition each. Backed by any `UserDefaults`: `.standard` in the app,
/// a throwaway suite in tests (tests must never touch the user's real preferences).
///
/// Only preferences live here. Current work (objective, if-then plan) belongs to
/// `ObjectiveTracker`, internal state to the type that owns it, and custom questions to
/// `CustomQuestionStore` (see the audit on #16).
nonisolated struct AppSettings {

    /// Stored key names. Raw values are what's on disk, so existing preferences and launch
    /// arguments (`scripts/run.sh -checkpointInterval 60`) keep working; never change one.
    enum Key: String, CaseIterable {
        case checkInInterval = "checkpointInterval"
        case randomness
        case checkInsEnabled = "checkpointsEnabled"
        case useActiveHours
        case activeHoursStart
        case activeHoursEnd
        case skipWeekdays
        case questionsPerCheckIn = "questionsPerCheckpoint"
        case disabledQuestionIDs
        case snoozeMinutes
        case maxSnoozes = "maxSnoozesPerCheckpoint"
        case afterMaxSnooze = "afterMaxSnoozeAction"
        case playSound = "playSoundOnCheckpoint"
        case soundName
        case respectFocus = "respectFocusMode"
        case holdDuringCalls
        case hideFromScreenCapture
        case showBreathingCue
        case fullScreenCheckIn = "fullScreenCheckpoint"
        case showFocusPill
        case menuBarDisplay
        case logResponses
        case goal1, goal2, goal3
        case objectivePromptShowMore
        case settingsPage
    }

    /// One default per setting. `@AppStorage` initial values use these too.
    enum Default {
        static let checkInInterval = 2700
        static let randomness = Randomness.medium
        static let checkInsEnabled = true
        static let useActiveHours = false
        static let activeHoursStart = 8
        static let activeHoursEnd = 18
        static let questionsPerCheckIn = 1
        static let snoozeMinutes = 5
        static let maxSnoozes = 2
        static let afterMaxSnooze = AfterMaxSnooze.autoDismiss
        static let playSound = true
        static let soundName = "Glass"
        static let respectFocus = true
        static let holdDuringCalls = true
        static let hideFromScreenCapture = true
        static let showBreathingCue = false
        static let fullScreenCheckIn = false
        static let showFocusPill = false
        static let menuBarDisplay = MenuBarDisplay.objectiveTime
        static let logResponses = true
        static let objectivePromptShowMore = false
        /// The Settings page that opens first: the last one viewed (#82).
        static let settingsPage = SettingsPage.now
    }

    /// What happens when "Not now" has been used the maximum number of times.
    enum AfterMaxSnooze: String, CaseIterable {
        /// Drop this check-in; the next comes after a full interval.
        case autoDismiss
        /// Show it once more, without "Not now".
        case forceModal
    }

    /// What the menu bar item shows.
    enum MenuBarDisplay: String, CaseIterable {
        case objectiveTime
        case countdown
    }

    static let goalKeys: [Key] = [.goal1, .goal2, .goal3]

    let defaults: UserDefaults

    init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Check-ins

    /// Base time between check-ins. Never zero or negative.
    var checkInInterval: TimeInterval {
        get { TimeInterval(positiveInt(.checkInInterval, Default.checkInInterval)) }
        nonmutating set { defaults.set(Int(newValue), forKey: Key.checkInInterval.rawValue) }
    }

    var randomness: Randomness {
        get { value(.randomness, Default.randomness) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.randomness.rawValue) }
    }

    var checkInsEnabled: Bool {
        get { bool(.checkInsEnabled, Default.checkInsEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.checkInsEnabled.rawValue) }
    }

    var questionsPerCheckIn: Int {
        get { positiveInt(.questionsPerCheckIn, Default.questionsPerCheckIn) }
        nonmutating set { defaults.set(newValue, forKey: Key.questionsPerCheckIn.rawValue) }
    }

    var disabledQuestionIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.disabledQuestionIDs.rawValue) ?? []) }
        nonmutating set { defaults.set(newValue.sorted(), forKey: Key.disabledQuestionIDs.rawValue) }
    }

    // MARK: - Schedule

    var useActiveHours: Bool {
        get { bool(.useActiveHours, Default.useActiveHours) }
        nonmutating set { defaults.set(newValue, forKey: Key.useActiveHours.rawValue) }
    }

    var activeHoursStart: Int {
        get { int(.activeHoursStart, Default.activeHoursStart) }
        nonmutating set { defaults.set(newValue, forKey: Key.activeHoursStart.rawValue) }
    }

    var activeHoursEnd: Int {
        get { int(.activeHoursEnd, Default.activeHoursEnd) }
        nonmutating set { defaults.set(newValue, forKey: Key.activeHoursEnd.rawValue) }
    }

    /// `Calendar` weekday numbers (1 = Sunday) with no check-ins.
    var skipWeekdays: [Int] {
        get { defaults.array(forKey: Key.skipWeekdays.rawValue) as? [Int] ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Key.skipWeekdays.rawValue) }
    }

    // MARK: - Snooze

    /// Minutes per "Not now". Never zero.
    var snoozeMinutes: Int {
        get { positiveInt(.snoozeMinutes, Default.snoozeMinutes) }
        nonmutating set { defaults.set(newValue, forKey: Key.snoozeMinutes.rawValue) }
    }

    /// How many times "Not now" can be used per check-in; 0 means unlimited.
    var maxSnoozes: Int {
        get { int(.maxSnoozes, Default.maxSnoozes) }
        nonmutating set { defaults.set(newValue, forKey: Key.maxSnoozes.rawValue) }
    }

    var afterMaxSnooze: AfterMaxSnooze {
        get { value(.afterMaxSnooze, Default.afterMaxSnooze) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.afterMaxSnooze.rawValue) }
    }

    /// Whether another "Not now" is allowed after `snoozeCount` of them.
    func allowsSnooze(after snoozeCount: Int) -> Bool {
        maxSnoozes == 0 || snoozeCount < maxSnoozes
    }

    // MARK: - Interruptions

    var playSound: Bool {
        get { bool(.playSound, Default.playSound) }
        nonmutating set { defaults.set(newValue, forKey: Key.playSound.rawValue) }
    }

    var soundName: String {
        get { defaults.string(forKey: Key.soundName.rawValue) ?? Default.soundName }
        nonmutating set { defaults.set(newValue, forKey: Key.soundName.rawValue) }
    }

    var respectFocus: Bool {
        get { bool(.respectFocus, Default.respectFocus) }
        nonmutating set { defaults.set(newValue, forKey: Key.respectFocus.rawValue) }
    }

    var holdDuringCalls: Bool {
        get { bool(.holdDuringCalls, Default.holdDuringCalls) }
        nonmutating set { defaults.set(newValue, forKey: Key.holdDuringCalls.rawValue) }
    }

    // MARK: - Appearance

    var hideFromScreenCapture: Bool {
        get { bool(.hideFromScreenCapture, Default.hideFromScreenCapture) }
        nonmutating set { defaults.set(newValue, forKey: Key.hideFromScreenCapture.rawValue) }
    }

    var showBreathingCue: Bool {
        get { bool(.showBreathingCue, Default.showBreathingCue) }
        nonmutating set { defaults.set(newValue, forKey: Key.showBreathingCue.rawValue) }
    }

    var fullScreenCheckIn: Bool {
        get { bool(.fullScreenCheckIn, Default.fullScreenCheckIn) }
        nonmutating set { defaults.set(newValue, forKey: Key.fullScreenCheckIn.rawValue) }
    }

    var showFocusPill: Bool {
        get { bool(.showFocusPill, Default.showFocusPill) }
        nonmutating set { defaults.set(newValue, forKey: Key.showFocusPill.rawValue) }
    }

    var menuBarDisplay: MenuBarDisplay {
        get { value(.menuBarDisplay, Default.menuBarDisplay) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.menuBarDisplay.rawValue) }
    }

    // MARK: - Data

    var logResponses: Bool {
        get { bool(.logResponses, Default.logResponses) }
        nonmutating set { defaults.set(newValue, forKey: Key.logResponses.rawValue) }
    }

    /// The non-empty goal lines, in order.
    var goals: [String] {
        Self.goalKeys.compactMap { key in
            let text = defaults.string(forKey: key.rawValue)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }
    }

    // MARK: - Reading

    // `integer(forKey:)` and `bool(forKey:)` also parse launch arguments (stored as strings),
    // but return 0 / false when unset, so "unset" is checked first to apply the default.

    private func int(_ key: Key, _ fallback: Int) -> Int {
        defaults.object(forKey: key.rawValue) == nil ? fallback : defaults.integer(forKey: key.rawValue)
    }

    private func positiveInt(_ key: Key, _ fallback: Int) -> Int {
        let value = int(key, fallback)
        return value > 0 ? value : fallback
    }

    private func bool(_ key: Key, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key.rawValue) == nil ? fallback : defaults.bool(forKey: key.rawValue)
    }

    private func value<T: RawRepresentable>(_ key: Key, _ fallback: T) -> T where T.RawValue == String {
        defaults.string(forKey: key.rawValue).flatMap(T.init(rawValue:)) ?? fallback
    }
}
