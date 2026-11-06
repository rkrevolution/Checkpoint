import SwiftUI

/// How often check-ins come and what they ask.
struct CheckInsSettingsPage: View {
    @EnvironmentObject private var customStore: CustomQuestionStore
    @EnvironmentObject private var objectiveTracker: ObjectiveTracker
    @AppStorage(AppSettings.Key.checkInsEnabled.rawValue) private var checkInsEnabled = AppSettings.Default.checkInsEnabled
    @AppStorage(AppSettings.Key.checkInInterval.rawValue) private var intervalSeconds = AppSettings.Default.checkInInterval
    @AppStorage(AppSettings.Key.randomness.rawValue) private var randomness = AppSettings.Default.randomness
    @AppStorage(AppSettings.Key.questionsPerCheckIn.rawValue) private var questionsPerCheckIn = AppSettings.Default.questionsPerCheckIn
    @State private var previewController: CheckpointWindowController?

    var body: some View {
        Form {
            Section {
                Toggle("Enable Checkpoints", isOn: $checkInsEnabled)
                SettingNote("Off stops check-ins until you turn them back on. To stop for a while, use Pause in the menu bar (⌃⌥⌘P).")
            }

            Section("Timing") {
                // Shows the nearest option for an unlisted value, but only saves when the user picks one
                Picker("Every", selection: Binding(
                    get: { IntervalOptions.nearest(to: intervalSeconds / 60) },
                    set: { intervalSeconds = $0 * 60 }
                )) {
                    ForEach(IntervalOptions.minutes, id: \.self) { mins in
                        Text(IntervalOptions.label(mins)).tag(mins)
                    }
                }
                Picker("Randomness", selection: $randomness) {
                    ForEach(Randomness.allCases) { level in
                        Text(level.label(for: TimeInterval(intervalSeconds))).tag(level)
                    }
                }
                SettingNote("Check-ins come at unpredictable times around the interval, so you can't brace for them. The range adjusts with the interval.")
            }

            Section("Each Check-in") {
                Picker("Questions", selection: $questionsPerCheckIn) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                }
                .pickerStyle(.segmented)
                SettingNote("One is usually best: a tap on the shoulder, not a form.")
                Button {
                    showPreview()
                } label: {
                    Label("Preview Checkpoint", systemImage: "eye")
                }
                SettingNote("See exactly what a check-in looks like with your current settings.")
            }
        }
        .formStyle(.grouped)
    }

    private func showPreview() {
        let bank = QuestionBank()
        bank.customStore = customStore
        let questions = bank.selectQuestions(count: questionsPerCheckIn)
        let session = CheckpointSession(questions: questions, intervalSeconds: intervalSeconds)
        let controller = CheckpointWindowController(
            session: session,
            currentObjective: objectiveTracker.current?.objective ?? "",
            checkpointNumber: 1,
            onDone: { [self] _, _ in previewController = nil },
            onSnooze: { [self] in previewController = nil }
        )
        previewController = controller
        controller.showWithFade()
    }
}
