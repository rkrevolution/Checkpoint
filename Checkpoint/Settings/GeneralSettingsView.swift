import AppKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var customStore: CustomQuestionStore
    @AppStorage("checkpointInterval") private var intervalSeconds = 2700
    @AppStorage("activeHoursStart") private var activeHoursStart = 8
    @AppStorage("activeHoursEnd") private var activeHoursEnd = 18
    @AppStorage("checkpointsEnabled") private var checkpointsEnabled = true
    @AppStorage("useActiveHours") private var useActiveHours = false
    @AppStorage("questionsPerCheckpoint") private var questionsPerCheckpoint = 1

    @State private var launchAtLogin = false
    @State private var previewController: CheckpointWindowController?

    private let intervalOptions = [1, 2, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120]

    var body: some View {
        Form {
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
                Text("Automatically start Checkpoint when you log in to your Mac.")
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
        .frame(width: 520, height: 480)
}
