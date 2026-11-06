import AppKit
import os.log

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "PresenceMonitor")

/// Whether the user is at the Mac, in one place (#18): away (system or display sleep,
/// screensaver, screen lock), idle (no input for a while), on a call, and macOS Focus.
///
/// It only observes and reports; the scheduler and the objective tracker decide what each change
/// means. Clock and idle reading are injected so the logic is testable with fake events.
@MainActor
final class PresenceMonitor {

    enum AwayReason: String, CaseIterable {
        case systemSleep, displaySleep, screensaver, screenLocked
    }

    /// The first away reason began (nothing was away before).
    var onAwayBegan: (() -> Void)?
    /// The last away reason ended; how long the user was away.
    var onAwayEnded: ((_ awayFor: TimeInterval) -> Void)?
    /// Idle started or ended, with the moment it really did (backdated to the last or first input).
    var onIdleChanged: ((_ isIdle: Bool, _ at: Date) -> Void)?
    var onCallChanged: ((_ isOnCall: Bool) -> Void)?
    var onFocusChanged: ((_ isActive: Bool) -> Void)?

    /// No input for this long counts as idle (time on the objective stops).
    static let idleThreshold: TimeInterval = 5 * 60

    private(set) var awayReasons = Set<AwayReason>()
    private(set) var isIdle = false
    private var awayStartedAt: Date?

    var isAway: Bool { !awayReasons.isEmpty }
    var isOnCall: Bool { callDetector.isInCall }
    var isFocusActive: Bool { focusObserver.isFocusActive }

    private let now: () -> Date
    private let idleSeconds: () -> TimeInterval
    private let callDetector: CallDetector
    private let focusObserver: FocusModeObserver

    init(
        now: @escaping () -> Date = Date.init,
        idleSeconds: @escaping () -> TimeInterval = PresenceMonitor.secondsSinceLastInput,
        callDetector: CallDetector? = nil,
        focusObserver: FocusModeObserver? = nil
    ) {
        self.now = now
        self.idleSeconds = idleSeconds
        self.callDetector = callDetector ?? CallDetector()
        self.focusObserver = focusObserver ?? FocusModeObserver()
    }

    /// Starts observing the system. Call once at launch, after the callbacks are set.
    func start() {
        observeAwayEvents()
        callDetector.onChange = { [weak self] inCall in self?.onCallChanged?(inCall) }
        callDetector.start()
        focusObserver.onFocusChanged = { [weak self] active in self?.onFocusChanged?(active) }
        focusObserver.startObserving()
    }

    // MARK: - Away

    func beginAway(_ reason: AwayReason) {
        let wasAway = isAway
        awayReasons.insert(reason)
        log.notice("━━━ AWAY: \(reason.rawValue, privacy: .public) (reasons=\(self.awayReasons.map(\.rawValue), privacy: .public)) ━━━")
        guard !wasAway else { return }
        awayStartedAt = now()
        onAwayBegan?()
    }

    func endAway(_ reason: AwayReason) {
        guard awayReasons.remove(reason) != nil else { return }
        log.notice("━━━ BACK: \(reason.rawValue, privacy: .public) (remaining=\(self.awayReasons.map(\.rawValue), privacy: .public)) ━━━")
        guard awayReasons.isEmpty else { return }
        let awayFor = awayStartedAt.map { now().timeIntervalSince($0) } ?? 0
        awayStartedAt = nil
        onAwayEnded?(awayFor)
    }

    private func observeAwayEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let events: [(NotificationCenter, String, AwayReason, Bool)] = [
            (workspace, NSWorkspace.willSleepNotification.rawValue, .systemSleep, true),
            (workspace, NSWorkspace.didWakeNotification.rawValue, .systemSleep, false),
            (workspace, NSWorkspace.screensDidSleepNotification.rawValue, .displaySleep, true),
            (workspace, NSWorkspace.screensDidWakeNotification.rawValue, .displaySleep, false),
            (distributed, "com.apple.screensaver.didstart", .screensaver, true),
            (distributed, "com.apple.screensaver.didstop", .screensaver, false),
            (distributed, "com.apple.screenIsLocked", .screenLocked, true),
            (distributed, "com.apple.screenIsUnlocked", .screenLocked, false),
        ]
        for (center, name, reason, isStart) in events {
            center.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if isStart { self?.beginAway(reason) } else { self?.endAway(reason) }
                }
            }
        }
    }

    // MARK: - Idle

    /// Polled periodically. Long stretches without keyboard or mouse input count as idle,
    /// backdated to the last input. Not while away or paused (those already stop the clock),
    /// and never on a call: you're working even without typing.
    func checkIdle(isPaused: Bool) {
        guard !isAway, !isPaused else { return }
        if isOnCall {
            if isIdle { setIdle(false, at: now()) }
            return
        }
        let idle = idleSeconds()
        if !isIdle, idle >= Self.idleThreshold {
            log.notice("Idle for \(Int(idle))s: not counting it as time on objective")
            setIdle(true, at: now().addingTimeInterval(-idle))
        } else if isIdle, idle < Self.idleThreshold {
            log.notice("Input resumed")
            setIdle(false, at: now().addingTimeInterval(-idle))
        }
    }

    private func setIdle(_ idle: Bool, at time: Date) {
        isIdle = idle
        onIdleChanged?(idle, time)
    }

    nonisolated static func secondsSinceLastInput() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    // MARK: - Debug

    #if DEBUG
    func debugSetFocus(_ active: Bool) { focusObserver.debugSetFocus(active) }
    func debugSetCall(_ inCall: Bool) { callDetector.debugOverride = inCall }
    #endif
}
