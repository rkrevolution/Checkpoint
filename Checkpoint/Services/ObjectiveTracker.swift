import Combine
import Foundation
import os.log

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "ObjectiveTracker")

/// Tracks how long the user has spent on their current objective (#24).
///
/// The open session is persisted in `defaults` so it survives relaunches; finished
/// sessions are appended to a JSON-lines file. Time away and time the app wasn't
/// running are excluded, and a session carried into a new day is closed and restarted.
@MainActor
final class ObjectiveTracker: ObservableObject {

    @Published private(set) var current: ObjectiveSession?

    private let defaults: UserDefaults
    private let now: () -> Date
    private let sessionsFile: JSONLinesFile<ObjectiveSession>
    private let calendar = Calendar.current
    /// End of the last away period, so a backdated start never overlaps time already excluded.
    private var lastAwayEndedAt: Date?

    private static let currentKey = "currentObjectiveSession"
    private static let lastSeenKey = "objectiveTrackerLastSeenAt"

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        sessionsURL: URL = JSONLinesFile<ObjectiveSession>.appSupportURL("sessions.jsonl")
    ) {
        self.defaults = defaults
        self.now = now
        self.sessionsFile = JSONLinesFile(url: sessionsURL)
        if let data = defaults.data(forKey: Self.currentKey) {
            current = try? JSONDecoder.iso8601.decode(ObjectiveSession.self, from: data)
        }
    }

    // MARK: - Lifecycle

    /// Call once at launch with the saved objective and if-then plan.
    func resume(objective: String, ifThenPlan: String?) {
        let t = now()
        let lastSeen = defaults.object(forKey: Self.lastSeenKey) as? Date

        if var session = current {
            if !calendar.isDate(session.startedAt, inSameDayAs: t) {
                // Don't stretch yesterday's session over the night
                end(at: lastSeen ?? session.startedAt)
            } else if let lastSeen, t > lastSeen {
                // The app wasn't running between lastSeen and now: count it as away
                session.awaySeconds += t.timeIntervalSince(lastSeen)
                session.awaySince = nil
                current = session
                save()
            }
        }
        if current == nil {
            start(objective: objective, ifThenPlan: ifThenPlan)
        }
        heartbeat()
    }

    /// Records that the app is alive, so downtime can be excluded after a relaunch.
    func heartbeat() {
        defaults.set(now(), forKey: Self.lastSeenKey)
    }

    // MARK: - Changes

    func objectiveChanged(to objective: String) {
        let trimmed = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != current?.objective else { return }
        let plan = current?.ifThenPlan
        end(at: now())
        start(objective: trimmed, ifThenPlan: plan)
    }

    func ifThenPlanChanged(to plan: String?) {
        guard var session = current else { return }
        let trimmed = plan?.trimmingCharacters(in: .whitespacesAndNewlines)
        session.ifThenPlan = (trimmed?.isEmpty ?? true) ? nil : trimmed
        current = session
        save()
    }

    func estimateChanged(to minutes: Int?) {
        guard var session = current else { return }
        session.estimateMinutes = (minutes ?? 0) > 0 ? minutes : nil
        current = session
        save()
    }

    /// Starts an away period, optionally backdated (e.g. to the last keyboard or mouse input).
    func beginAway(at time: Date? = nil) {
        guard var session = current, session.awaySince == nil else { return }
        let t = now()
        var start = min(time ?? t, t)
        if let lastAwayEndedAt { start = max(start, lastAwayEndedAt) }
        session.awaySince = max(start, session.startedAt)
        current = session
        save()
    }

    /// Ends the away period, optionally backdated (e.g. to when input resumed).
    func endAway(at time: Date? = nil) {
        guard var session = current, let since = session.awaySince else { return }
        let end = max(since, min(time ?? now(), now()))
        session.awaySeconds += end.timeIntervalSince(since)
        session.awaySince = nil
        lastAwayEndedAt = end
        current = session
        save()
    }

    // MARK: - Queries

    /// Active time on the current objective, or nil if there is none.
    func activeSeconds() -> TimeInterval? {
        current.map { $0.activeSeconds(at: now()) }
    }

    /// Today's sessions (finished and current), oldest first.
    func todaySessions() -> [ObjectiveSession] {
        let t = now()
        return allSessions().filter { calendar.isDate($0.startedAt, inSameDayAs: t) }
    }

    /// Sessions that started in the last `days` days (finished and current), oldest first.
    func sessions(lastDays days: Int) -> [ObjectiveSession] {
        let cutoff = now().addingTimeInterval(-Double(days) * 24 * 3600)
        return allSessions().filter { $0.startedAt >= cutoff }
    }

    private func allSessions() -> [ObjectiveSession] {
        ((try? sessionsFile.loadAll()) ?? []) + (current.map { [$0] } ?? [])
    }

    /// Distinct objectives from the last week, most recent first (for one-tap suggestions).
    func recentObjectives(limit: Int = 5) -> [String] {
        let cutoff = now().addingTimeInterval(-7 * 24 * 3600)
        let finished = (try? sessionsFile.loadAll()) ?? []
        var seen = Set<String>()
        var result: [String] = []
        for session in (finished + (current.map { [$0] } ?? [])).reversed() where session.startedAt >= cutoff {
            if seen.insert(session.objective).inserted {
                result.append(session.objective)
            }
            if result.count == limit { break }
        }
        return result
    }

    // MARK: - Private

    private func start(objective: String, ifThenPlan: String?) {
        guard !objective.isEmpty else {
            current = nil
            save()
            return
        }
        current = ObjectiveSession(
            id: UUID(),
            objective: objective,
            ifThenPlan: ifThenPlan,
            startedAt: now(),
            endedAt: nil,
            awaySeconds: 0,
            awaySince: nil
        )
        log.notice("Objective session started")
        save()
    }

    private func end(at time: Date) {
        guard var session = current else { return }
        session.endedAt = max(time, session.startedAt)
        if let since = session.awaySince {
            session.awaySeconds += max(0, session.endedAt!.timeIntervalSince(since))
            session.awaySince = nil
        }
        sessionsFile.append(session)
        log.notice("Objective session ended: active \(Int(session.activeSeconds(at: time)))s")
        current = nil
        save()
    }

    private func save() {
        if let current, let data = try? JSONEncoder.iso8601.encode(current) {
            defaults.set(data, forKey: Self.currentKey)
        } else {
            defaults.removeObject(forKey: Self.currentKey)
        }
    }
}
