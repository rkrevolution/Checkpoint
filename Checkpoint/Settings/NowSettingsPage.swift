import SwiftUI

/// What you're working on right now, for how long, and the goals kept in view.
struct NowSettingsPage: View {
    @EnvironmentObject private var objectiveTracker: ObjectiveTracker
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var commands: AppCommands
    @AppStorage(AppSettings.Key.goal1.rawValue) private var goal1 = ""
    @AppStorage(AppSettings.Key.goal2.rawValue) private var goal2 = ""
    @AppStorage(AppSettings.Key.goal3.rawValue) private var goal3 = ""

    var body: some View {
        Form {
            Section("Working On") {
                // Refreshes the time while Settings is open
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 6) {
                        if let session = objectiveTracker.current {
                            HStack(spacing: 6) {
                                Image(systemName: "target")
                                    .foregroundStyle(.orange)
                                Text(session.objective)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .lineLimit(2)
                            }
                            Text(session.progressText(at: context.date))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(session.isOverEstimate(at: context.date) ? .red : .orange)
                                .monospacedDigit()
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
                HStack {
                    Text(checkInStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(objectiveTracker.current == nil ? "Set Objective…" : "Change…") {
                        commands.changeObjective()
                    }
                }
                SettingNote("Time counts only while you're on a stated objective and at your Mac, not while paused, away or idle.")
            }

            Section("Goals") {
                TextField("Goal 1", text: $goal1, prompt: Text("e.g. Ship Checkpoint 1.0"))
                TextField("Goal 2", text: $goal2, prompt: Text("e.g. Run 3× a week"))
                TextField("Goal 3", text: $goal3, prompt: Text("Optional"))
                SettingNote("Up to three, shown in full on every check-in and when you choose what to work on, and kept in the menu and Today.")
            }
        }
        .formStyle(.grouped)
    }

    private var checkInStatus: String {
        switch appState.state {
        case .idle, .triggered: return "Check-ins running"
        case .presenting: return "Check-in on screen"
        case .snoozed: return "Check-in snoozed"
        case .paused: return "Check-ins paused"
        case .outsideHours: return "Outside active hours"
        case .focusModeActive: return "Held during Focus"
        }
    }
}
