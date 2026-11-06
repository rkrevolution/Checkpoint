import Foundation

/// The one answer to "can a check-in show now?" (#17). Every path that presents a check-in asks
/// it: the scheduled timer, a snooze coming back, a check-in held for a call, and Check In Now.
///
/// Pure: it decides from a snapshot of the conditions and leaves the side effects (state
/// changes, holding for a call, the day summary) to the caller.
nonisolated struct CheckInGate {

    /// Who is asking.
    enum Request: Equatable {
        /// The interval timer fired, or a check-in held for a call is being delivered.
        case scheduled
        /// A snoozed check-in's time is up.
        case snoozeReturn
        /// The user chose Check In Now: an explicit request, so only away, paused and an
        /// already open check-in stop it.
        case manual
    }

    /// Why a check-in can't show now.
    enum Block: Equatable {
        /// Asleep, display asleep, screensaver or locked. Nothing ever shows over these.
        case away
        /// Paused from the menu. Only Resume ends it; nothing automatic overrides it.
        case paused
        /// Another check-in is open or snoozed (or, for a snooze return, this one was cancelled).
        case inProgress
        /// Check-ins are off, it's a skipped weekday, or outside active hours.
        case schedule(outsideActiveHours: Bool)
        /// macOS Focus is on and the user asked Checkpoint to respect it.
        case focus
        /// On a call and "hold during calls" is on: show it when the call ends.
        case call

        /// Whether the check-in should wait and show later, rather than be skipped.
        var waits: Bool { self == .call }
    }

    /// A snapshot of everything the decision depends on.
    struct Conditions: Equatable {
        var state: CheckpointState
        var isAway = false
        /// `ScheduleManager.shouldFire()`: enabled, weekday, active hours.
        var scheduleAllows = true
        var withinActiveHours = true
        var isFocusActive = false
        var respectFocus = true
        var isOnCall = false
        var holdDuringCalls = true
    }

    /// Nil means show it now.
    static func block(_ request: Request, _ c: Conditions) -> Block? {
        if c.isAway { return .away }
        if c.state == .paused { return .paused }
        if let busy = stateBlock(request, c.state) { return busy }
        guard request != .manual else { return nil }
        if !c.scheduleAllows { return .schedule(outsideActiveHours: !c.withinActiveHours) }
        if focusBlocks(isFocusActive: c.isFocusActive, respectFocus: c.respectFocus) { return .focus }
        if c.isOnCall && c.holdDuringCalls { return .call }
        return nil
    }

    /// Whether Focus holds check-ins back. Also decides whether the menu bar says "Focus" (#50).
    static func focusBlocks(isFocusActive: Bool, respectFocus: Bool) -> Bool {
        isFocusActive && respectFocus
    }

    /// Which states leave room for this request.
    private static func stateBlock(_ request: Request, _ state: CheckpointState) -> Block? {
        switch (request, state) {
        case (.snoozeReturn, .snoozed):
            return nil
        case (.snoozeReturn, _):
            return .inProgress  // the snooze was cancelled or replaced
        case (_, .presenting), (_, .triggered):
            return .inProgress
        case (.scheduled, .snoozed):
            return .inProgress  // the snoozed one comes back on its own
        default:
            // idle, outsideHours and focusModeActive are waiting states: the gate re-decides them
            return nil
        }
    }
}
