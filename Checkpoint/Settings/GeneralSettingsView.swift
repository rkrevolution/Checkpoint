import AppKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var customStore: CustomQuestionStore
    @EnvironmentObject private var objectiveTracker: ObjectiveTracker
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var commands: AppCommands
    @AppStorage("checkpointInterval") private var intervalSeconds = 2700
    @AppStorage("activeHoursStart") private var activeHoursStart = 8
    @AppStorage("activeHoursEnd") private var activeHoursEnd = 18
    @AppStorage("checkpointsEnabled") private var checkpointsEnabled = true
    @AppStorage("useActiveHours") private var useActiveHours = false
    @AppStorage("questionsPerCheckpoint") private var questionsPerCheckpoint = 1
    @AppStorage("menuBarDisplay") private var menuBarDisplay = "objectiveTime"
    @AppStorage("goal1") private var goal1 = ""
    @AppStorage("goal2") private var goal2 = ""
    @AppStorage("goal3") private var goal3 = ""

    @State private var launchAtLogin = false
    @State private var skipWeekdays: [Int] = UserDefaults.standard.array(forKey: "skipWeekdays") as? [Int] ?? []
    @State private var previewController: CheckpointWindowController?

    private let intervalOptions = [1, 2, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120]

    var body: some View {
        Form {
            nowSection

            Section("Goals") {
                TextField("Goal 1", text: $goal1, prompt: Text("e.g. Ship Checkpoint 1.0"))
                TextField("Goal 2", text: $goal2, prompt: Text("e.g. Run 3× a week"))
                TextField("Goal 3", text: $goal3, prompt: Text("Optional"))
                Text("Up to three, kept in view in the menu, on check-ins and in Today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Start at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            // Revert toggle on failure
                            launchAtLogin = !newValue
                        }
                    }
                Text("Automatically start Checkpoint when you log in to your Mac. Press ⌃⌥⌘P in any app to pause or resume check-ins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable Checkpoints", isOn: $checkpointsEnabled)
            }

            Section("Check-in Interval") {
                Picker("Every", selection: Binding(
                    get: { intervalSeconds / 60 },
                    set: { intervalSeconds = $0 * 60 }
                )) {
                    ForEach(intervalOptions, id: \.self) { mins in
                        Text(intervalLabel(mins)).tag(mins)
                    }
                }
            }

            Section("Active Hours") {
                Toggle("Limit to active hours", isOn: $useActiveHours)

                if useActiveHours {
                    HStack {
                        Picker("Start", selection: $activeHoursStart) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(hourLabel(hour)).tag(hour)
                            }
                        }
                        .frame(width: 160)

                        Text("to")
                            .foregroundStyle(.secondary)

                        Picker("End", selection: $activeHoursEnd) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(hourLabel(hour)).tag(hour)
                            }
                        }
                        .frame(width: 160)
                    }

                    Text("Checkpoints only fire during these hours.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Weekday skipping (#29): days shown in the user's calendar order
                HStack(spacing: 4) {
                    Text("Check in on")
                    Spacer()
                    ForEach(Weekdays.ordered(), id: \.self) { weekday in
                        Toggle(Weekdays.shortName(weekday), isOn: Binding(
                            get: { !skipWeekdays.contains(weekday) },
                            set: { on in
                                skipWeekdays = Weekdays.setSkipped(weekday, skipped: !on, in: skipWeekdays)
                                UserDefaults.standard.set(skipWeekdays, forKey: "skipWeekdays")
                            }
                        ))
                        .toggleStyle(.button)
                        .controlSize(.small)
                    }
                }
            }

            Section("Menu Bar") {
                Picker("Show", selection: $menuBarDisplay) {
                    Text("Time on current objective").tag("objectiveTime")
                    Text("Countdown to next check-in").tag("countdown")
                }
                Text("Time on your objective keeps time visible. A countdown lets you anticipate check-ins, which makes them less effective.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Questions per Check-in") {
                Picker("Questions", selection: $questionsPerCheckpoint) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button {
                    showPreview()
                } label: {
                    Label("Preview Checkpoint", systemImage: "eye")
                }
                Text("See exactly what a checkpoint looks like with your current settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text(AppInfo.displayString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                    Button("How Checkpoint Works…") { commands.showHowItWorks() }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled

            // Snap to nearest option if current value isn't in the list
            let currentMins = intervalSeconds / 60
            if !intervalOptions.contains(currentMins) {
                let nearest = intervalOptions.min(by: { abs($0 - currentMins) < abs($1 - currentMins) }) ?? 45
                intervalSeconds = nearest * 60
            }
        }
    }

    // MARK: - Now

    /// What the app thinks you're working on right now, and for how long.
    private var nowSection: some View {
        Section("Now") {
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
        }
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

    private func showPreview() {
        let bank = QuestionBank()
        bank.customStore = customStore
        let questions = bank.selectQuestions(count: questionsPerCheckpoint)
        let session = CheckpointSession(
            id: UUID(),
            timestamp: Date(),
            intervalSeconds: intervalSeconds,
            questionsShown: questions,
            responses: questions.map { QuestionResponse(questionId: $0.id, text: "") },
            outcome: .completed
        )
        let mins = max(1, intervalSeconds / 60)
        let objective = UserDefaults.standard.string(forKey: "currentObjective") ?? ""
        let wc = CheckpointWindowController(
            session: session,
            currentObjective: objective,
            nextCheckpointEstimate: "~\(mins) min",
            checkpointNumber: 1,
            onDone: { [self] _, _ in previewController = nil },
            onSnooze: { [self] in previewController = nil }
        )
        previewController = wc
        wc.showWithFade()
    }

    private func intervalLabel(_ mins: Int) -> String {
        switch mins {
        case 1: return "1 min"
        case 60: return "1 hour"
        case 90: return "1.5 hours"
        case 120: return "2 hours"
        default: return "\(mins) min"
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
}

#Preview {
    GeneralSettingsView()
        .environmentObject(CustomQuestionStore())
        .environmentObject(AppState())
        .environmentObject(AppCommands())
        .environmentObject(ObjectiveTracker(
            defaults: UserDefaults(suiteName: "preview")!,
            sessionsURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview-sessions.jsonl")
        ))
        .frame(width: 520, height: 480)
}
