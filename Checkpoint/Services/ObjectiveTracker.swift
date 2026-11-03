import Foundation
import os.log

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "ObjectiveTracker")

/// Tracks how long the user has spent on their current objective (#24).
///
/// The open session is persisted in `defaults` so it survives relaunches; finished
/// sessions are appended to a JSON-lines file. Time away and time the app wasn't
/// running are excluded, and a session carried into a new day is closed and restarted.
@MainActor
final class ObjectiveTracker {

    private(set) var current: ObjectiveSession?

    private let defaults: UserDefaults
    private let now: () -> Date
    private let sessionsFile: JSONLinesFile<ObjectiveSession>
    private let calendar = Calendar.current

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

    func beginAway() {
        guard var session = current, session.awaySince == nil else { return }
        session.awaySince = now()
        current = session
        save()
    }

    func endAway() {
        guard var session = current, let since = session.awaySince else { return }
        session.awaySeconds += max(0, now().timeIntervalSince(since))
        session.awaySince = nil
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
        let finished = (try? sessionsFile.loadAll()) ?? []
        let all = finished + (current.map { [$0] } ?? [])
        return all.filter { calendar.isDate($0.startedAt, inSameDayAs: t) }
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
