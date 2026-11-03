import SwiftUI

/// The checkpoint card. Hierarchy, top to bottom:
/// 1. the real time (largest), 2. what you're on and for how long, 3. one grounding question,
/// 4. a one-tap answer: On track / Drifted / Switched (#12). Drifted shows the if-then plan and
/// a field to park the distraction (#34); Switched picks a recent objective or a new one.
struct CheckpointView: View {
    let session: CheckpointSession
    let currentObjective: String
    let nextCheckpointEstimate: String
    let checkpointNumber: Int
    /// Time spent on the current objective (#10), and its if-then plan (#32)
    let objectiveSession: ObjectiveSession?
    let recentObjectives: [String]
    let allowSnooze: Bool
    var onDone: ((CheckpointSession, String?) -> Void)?
    var onSnooze: (() -> Void)?

    private enum Mode { case ask, drifted, switched }

    @State private var mode: Mode = .ask
    @State private var buttonsEnabled = false
    @State private var appeared = false
    @State private var newObjective = ""
    @State private var parked = ""
    @State private var breathScale: CGFloat = 1.0
    @FocusState private var fieldFocused: Bool

    @AppStorage("showBreathingCue") private var showBreathingCue = false

    init(session: CheckpointSession,
         currentObjective: String = "",
         nextCheckpointEstimate: String = "",
         checkpointNumber: Int = 1,
         objectiveSession: ObjectiveSession? = nil,
         recentObjectives: [String] = [],
         allowSnooze: Bool = true,
         onDone: ((CheckpointSession, String?) -> Void)? = nil,
         onSnooze: (() -> Void)? = nil) {
        self.session = session
        self.currentObjective = currentObjective
        self.nextCheckpointEstimate = nextCheckpointEstimate
        self.checkpointNumber = checkpointNumber
        self.objectiveSession = objectiveSession
        self.recentObjectives = recentObjectives.filter { $0 != currentObjective }
        self.allowSnooze = allowSnooze
        self.onDone = onDone
        self.onSnooze = onSnooze
    }

    var body: some View {
        VStack(spacing: 0) {
            timeAnchor
                .padding(.bottom, 14)

            objectiveSection
                .padding(.bottom, 14)

            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
                .padding(.horizontal, 40)
                .padding(.bottom, 14)

            Group {
                switch mode {
                case .ask: askSection
                case .drifted: driftedSection
                case .switched: switchedSection
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            footer
        }
        .padding(28)
        .frame(width: 440, height: 440)
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                buttonsEnabled = true
            }
        }
    }

    // MARK: - 1. Time

    private var timeAnchor: some View {
        VStack(spacing: 4) {
            Text(session.timestamp, style: .time)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("\(DurationText.long(TimeInterval(session.intervalSeconds))) since your last check-in")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4), value: appeared)
    }

    // MARK: - 2. Objective and time on it

    @ViewBuilder
    private var objectiveSection: some View {
        if currentObjective.isEmpty {
            Text("No objective set")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text(currentObjective)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                if let objectiveSession, objectiveSession.objective == currentObjective {
                    let since = objectiveSession.startedAt.formatted(date: .omitted, time: .shortened)
                    Text("for \(DurationText.long(objectiveSession.activeSeconds(at: session.timestamp))) · since \(since)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 24)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.15), value: appeared)
        }
    }

    // MARK: - 3–4. Question and one-tap answer

    private var askSection: some View {
        VStack(spacing: 14) {
            ForEach(session.questionsShown) { question in
                Text(question.text)
                    .font(.system(size: 15, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if session.questionsShown.isEmpty {
                Text("Are you still on track?")
                    .font(.system(size: 15, weight: .medium))
            }

            if showBreathingCue {
                Circle()
                    .fill(.orange.opacity(0.12))
                    .frame(width: 24, height: 24)
                    .scaleEffect(breathScale)
                    .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: breathScale)
                    .onAppear { breathScale = 1.6 }
            }

            VStack(spacing: 6) {
                Text("Right now I'm…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button {
                        finish(.onTrack)
                    } label: {
                        Label("On track", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut(.defaultAction)

                    Button {
                        mode = .drifted
                        fieldFocused = true
                    } label: {
                        Label("Drifted", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        mode = .switched
                        fieldFocused = true
                    } label: {
                        Label("Switched", systemImage: "arrow.left.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                }
                .controlSize(.large)
                .disabled(!buttonsEnabled)
                .opacity(buttonsEnabled ? 1 : 0.35)
                .animation(.easeIn(duration: 0.3), value: buttonsEnabled)
            }
        }
        .padding(.horizontal, 4)
    }

    private var driftedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let plan = objectiveSession?.ifThenPlan {
                Label("Your plan: \(plan)", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No problem. What pulled you away?")
                    .font(.system(size: 14, weight: .medium))
            }
            TextField("Park it here to deal with later (optional)", text: $parked)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { finish(.drifted) }
            HStack {
                Button("Back") { mode = .ask }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Back to \(currentObjective.isEmpty ? "work" : "it")") { finish(.drifted) }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
    }

    private var switchedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What are you working on now?")
                .font(.system(size: 14, weight: .medium))
            HStack(spacing: 4) {
                TextField("New objective", text: $newObjective)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit { finish(.switched) }
                Menu {
                    if recentObjectives.isEmpty {
                        Text("No recent objectives yet")
                    } else {
                        Section("Recent objectives") {
                            ForEach(recentObjectives, id: \.self) { recent in
                                Button(recent) { newObjective = recent }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            if !recentObjectives.isEmpty {
                HStack(spacing: 6) {
                    ForEach(recentObjectives.prefix(3), id: \.self) { recent in
                        Button(recent) { newObjective = recent }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .lineLimit(1)
                    }
                }
            }
            HStack {
                Button("Back") { mode = .ask }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Switch") { finish(.switched) }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(trimmed(newObjective).isEmpty)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if !allowSnooze {
                Text("Snooze limit reached")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
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
            }
            Spacer()
            Text(checkpointNumber > 0 ? "\u{2713} \(checkpointNumber) today" : "")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(buttonsEnabled ? "· next \(nextCheckpointEstimate)" : "")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(height: 18)
        .padding(.top, 8)
    }

    // MARK: - Finishing

    private func finish(_ response: CheckInResponse) {
        var updated = session
        updated.outcome = .completed
        updated.checkInResponse = response
        updated.responses = session.questionsShown.map { QuestionResponse(questionId: $0.id, text: "") }
        let thought = trimmed(parked)
        updated.parkedThought = (response == .drifted && !thought.isEmpty) ? thought : nil

        let switchedTo = trimmed(newObjective)
        let updatedObjective = (response == .switched && !switchedTo.isEmpty && switchedTo != currentObjective)
            ? switchedTo : nil
        onDone?(updated, updatedObjective)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    let question = Question(
        id: "preview",
        text: "What were you doing just before this appeared?",
        isEnabled: true,
        isCustom: false,
        categoryId: "awareness"
    )
    let session = CheckpointSession(
        id: UUID(),
        timestamp: Date(),
        intervalSeconds: 2700,
        questionsShown: [question],
        responses: [QuestionResponse(questionId: "preview", text: "")],
        outcome: .completed
    )
    CheckpointView(
        session: session,
        currentObjective: "Finish the settings migration",
        nextCheckpointEstimate: "~45 min",
        checkpointNumber: 3,
        objectiveSession: ObjectiveSession(
            id: UUID(), objective: "Finish the settings migration", ifThenPlan: "close the extra tabs",
            startedAt: Date().addingTimeInterval(-4800), endedAt: nil, awaySeconds: 0, awaySince: nil
        ),
        recentObjectives: ["Email", "Slides"]
    )
}
