import SwiftUI

struct CheckpointView: View {
    let session: CheckpointSession
    let currentObjective: String
    let nextCheckpointEstimate: String
    let checkpointNumber: Int
    var onDone: ((CheckpointSession, String?) -> Void)?
    var onSnooze: (() -> Void)?

    @State private var buttonsEnabled = false
    @State private var appeared = false
    @State private var isEditingObjective = false
    @State private var editedObjective = ""
    @State private var breathScale: CGFloat = 1.0

    @AppStorage("showBreathingCue") private var showBreathingCue = false

    init(session: CheckpointSession,
         currentObjective: String = "",
         nextCheckpointEstimate: String = "",
         checkpointNumber: Int = 1,
         onDone: ((CheckpointSession, String?) -> Void)? = nil,
         onSnooze: (() -> Void)? = nil) {
        self.session = session
        self.currentObjective = currentObjective
        self.nextCheckpointEstimate = nextCheckpointEstimate
        self.checkpointNumber = checkpointNumber
        self.onDone = onDone
        self.onSnooze = onSnooze
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // MARK: - Time anchor (fights time blindness)
            VStack(spacing: 6) {
                Text(session.timestamp, style: .time)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .opacity(appeared ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.4), value: appeared)

                let mins = session.intervalSeconds / 60
                Text("\(mins) minutes have passed")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .opacity(appeared ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.4).delay(0.15), value: appeared)
            }
            .padding(.bottom, 16)

            // MARK: - Current objective (working memory cue)
            objectiveSection
                .opacity(appeared ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)
                .padding(.bottom, 12)

            // MARK: - Divider
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
                .padding(.horizontal, 40)
                .padding(.bottom, 14)

            // MARK: - The grounding question
            VStack(spacing: 12) {
                ForEach(session.questionsShown) { question in
                    Text(question.text)
                        .font(.system(size: 16, weight: .medium))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 28)
            .opacity(appeared ? 1.0 : 0.0)
            .offset(y: appeared ? 0 : 8)
            .animation(.easeOut(duration: 0.5).delay(0.35), value: appeared)

            if session.questionsShown.isEmpty {
                Text("Are you still on track?")
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.center)
            }

            // MARK: - Breathing cue (vagal tone regulation)
            if showBreathingCue {
                Circle()
                    .fill(.orange.opacity(0.12))
                    .frame(width: 28, height: 28)
                    .scaleEffect(breathScale)
                    .animation(
                        .easeInOut(duration: 4.0).repeatForever(autoreverses: true),
                        value: breathScale
                    )
                    .padding(.top, 10)
                    .onAppear {
                        breathScale = 1.6
                    }
            }

            Spacer()

            // MARK: - Actions (two buttons)
            HStack(spacing: 12) {
                let snoozeMin = max(1, UserDefaults.standard.integer(forKey: "snoozeMinutes"))
                Button {
                    onSnooze?()
                } label: {
                    Text("Not now (\(snoozeMin)m)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!buttonsEnabled)

                Spacer()

                Button {
                    let updatedObjective = isEditingObjective ? editedObjective.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                    onDone?(buildSession(outcome: .completed), updatedObjective)
                } label: {
                    Text("Got it")
                        .font(.system(size: 13, weight: .medium))
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(!buttonsEnabled)
            }
            .opacity(buttonsEnabled ? 1.0 : 0.3)
            .animation(.easeIn(duration: 0.3), value: buttonsEnabled)

            // MARK: - Footer (streak counter + next estimate)
            HStack {
                Text(checkpointNumber > 0 ? "\u{2713} \(checkpointNumber) checkpoint\(checkpointNumber == 1 ? "" : "s") today" : "")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(buttonsEnabled ? nextCheckpointEstimate : "")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .frame(height: 14)
            .padding(.top, 6)
        }
        .padding(28)
        .frame(width: 420, height: 380)
        .onAppear {
            appeared = true
            editedObjective = currentObjective
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                buttonsEnabled = true
            }
        }
    }

    // MARK: - Objective Section

    @ViewBuilder
    private var objectiveSection: some View {
        if isEditingObjective {
            // Inline edit mode
            VStack(spacing: 6) {
                TextField("What are you working on?", text: $editedObjective)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .frame(maxWidth: 300)
                    .onSubmit {
                        isEditingObjective = false
                    }
            }
            .padding(.horizontal, 40)
        } else if !currentObjective.isEmpty {
            // Show existing objective as passive cue — visually distinct
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text(currentObjective)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                Button {
                    isEditingObjective = true
                } label: {
                    Text("update")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
        } else {
            // No objective set — prompt to set one
            Button {
                isEditingObjective = true
            } label: {
                Text("Set current objective")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func buildSession(outcome: CheckpointSession.Outcome) -> CheckpointSession {
        var updated = session
        updated.outcome = outcome
        updated.responses = session.questionsShown.map { QuestionResponse(questionId: $0.id, text: "") }
        return updated
    }
}
