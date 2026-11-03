import AppKit
import SwiftUI

/// "Today" window: what you're on now, today's objectives with time and estimates,
/// check-in answers, estimate accuracy this week, and parked thoughts.
/// Opened from the menu bar at any time, and at the end of active hours.
final class TodayWindowController: NSWindowController {

    init(tracker: ObjectiveTracker,
         parked: ParkedThoughts,
         loadCheckIns: @escaping () -> [CheckpointSession],
         headline: String? = nil) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        #if DEBUG
        window.title = "Today (Debug)"
        #else
        window.title = "Today"
        #endif
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        let view = TodayView(headline: headline, loadCheckIns: loadCheckIns)
            .environmentObject(tracker)
            .environmentObject(parked)
        window.contentView = NSHostingView(rootView: view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

// MARK: - SwiftUI View

struct TodayView: View {
    let headline: String?
    let loadCheckIns: () -> [CheckpointSession]

    @EnvironmentObject private var tracker: ObjectiveTracker
    @EnvironmentObject private var parked: ParkedThoughts

    var body: some View {
        // Refresh times and check-ins while the window is open
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let sessions = tracker.todaySessions()
            let checkIns = loadCheckIns().filter { Calendar.current.isDate($0.timestamp, inSameDayAs: now) }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(now)
                    nowSection(now)
                    timeline(sessions, now)
                    checkInSection(checkIns)
                    estimateSection(now)
                    parkedSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 380, minHeight: 420)
    }

    // MARK: Sections

    private func header(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let headline {
                Text(headline)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            Text(now.formatted(date: .complete, time: .omitted))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(now.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func nowSection(_ now: Date) -> some View {
        section("Now") {
            if let session = tracker.current {
                Label(session.objective, systemImage: "target")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(session.progressText(at: now))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(session.isOverEstimate(at: now) ? .red : .orange)
                    .monospacedDigit()
                if let minutes = session.estimateMinutes {
                    ProgressView(value: min(1, session.activeSeconds(at: now) / (Double(minutes) * 60)))
                        .tint(session.isOverEstimate(at: now) ? .red : .orange)
                }
                if let plan = session.ifThenPlan {
                    Label("If I drift: \(plan)", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No objective set")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timeline(_ sessions: [ObjectiveSession], _ now: Date) -> some View {
        section("Today") {
            if sessions.isEmpty {
                Text("Nothing tracked yet today.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions) { session in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        Text(session.objective)
                            .font(.system(size: 13, weight: session.endedAt == nil ? .semibold : .regular))
                            .lineLimit(1)
                        Spacer()
                        Text(DurationText.long(session.activeSeconds(at: now)))
                            .font(.system(size: 12).monospacedDigit())
                        if let minutes = session.estimateMinutes {
                            Text("est. \(DurationText.short(Double(minutes) * 60))")
                                .font(.system(size: 11))
                                .foregroundStyle(session.isOverEstimate(at: now) ? .red : .secondary)
                        }
                    }
                }
                let total = sessions.reduce(0) { $0 + $1.activeSeconds(at: now) }
                Text("Total: \(DurationText.long(total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func checkInSection(_ checkIns: [CheckpointSession]) -> some View {
        section("Check-ins") {
            if checkIns.isEmpty {
                Text("No check-ins yet today.")
                    .foregroundStyle(.secondary)
            } else {
                let answered = checkIns.compactMap(\.checkInResponse)
                let snoozed = checkIns.filter { $0.outcome == .snoozed }.count
                let parts = CheckInResponse.allCases.compactMap { response -> String? in
                    let count = answered.filter { $0 == response }.count
                    return count > 0 ? "\(response.label) \(count)" : nil
                } + (snoozed > 0 ? ["Snoozed \(snoozed)"] : [])
                Text(parts.joined(separator: " · "))
                    .font(.system(size: 13))
            }
        }
    }

    private func estimateSection(_ now: Date) -> some View {
        section("Estimates, last 7 days") {
            if let ratio = EstimateStats.ratio(tracker.sessions(lastDays: 7), at: now) {
                Text("Tasks \(EstimateStats.describe(ratio)).")
                    .font(.system(size: 13, weight: .medium))
                if ratio > 1.1 {
                    Text("Try padding new estimates by about \(Int(((ratio - 1) * 100).rounded()))%.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Pick \"Should take about\" when you set an objective to see how your guesses compare.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var parkedSection: some View {
        if !parked.open.isEmpty {
            section("Parked for later") {
                ForEach(parked.open) { thought in
                    HStack {
                        Button {
                            parked.markDone(thought.id)
                        } label: {
                            Image(systemName: "circle")
                        }
                        .buttonStyle(.plain)
                        .help("Mark done")
                        Text(thought.text)
                            .font(.system(size: 13))
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
