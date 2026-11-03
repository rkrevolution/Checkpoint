import SwiftUI

/// The checkpoint card. Hierarchy, top to bottom:
/// 1. the real time (largest), 2. what you're on and for how long, 3. one grounding question,
/// 4. a one-tap answer: On track / Drifted / Switched (#12). Drifted shows the if-then plan and
/// a field to park the distraction (#34); Switched picks a recent objective or a new one.
struct CheckpointView: View {
    let session: CheckpointSession
    let currentObjective: String
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
    private let goals = Goals.current()

    init(session: CheckpointSession,
         currentObjective: String = "",
         checkpointNumber: Int = 1,
         objectiveSession: ObjectiveSession? = nil,
         recentObjectives: [String] = [],
         allowSnooze: Bool = true,
         onDone: ((CheckpointSession, String?) -> Void)? = nil,
         onSnooze: (() -> Void)? = nil) {
        self.session = session
        self.currentObjective = currentObjective
        self.checkpointNumber = checkpointNumber
        self.objectiveSession = objectiveSession
        self.recentObjectives = recentObjectives.filter { !ObjectiveName.same($0, currentObjective) }
        self.allowSnooze = allowSnooze
        self.onDone = onDone
        self.onSnooze = onSnooze
    }

    var body: some View {
        VStack(spacing: 0) {
            timeAnchor
                .padding(.bottom, 14)

            objectiveSection
                .padding(.bottom, goals.isEmpty ? 14 : 6)

            if !goals.isEmpty {
                Text("Goals: " + goals.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }

            // With no objective, the "What are you working on?" picker above is the only question
            if !(mode == .ask && currentObjective.isEmpty) {
                Rectangle()
                    .fill(.separator)
                    .frame(height: 0.5)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 14)

                switch mode {
                case .ask: askSection
                case .drifted: driftedSection
                case .switched: switchedSection
                }
            }

            footer
                .padding(.top, 14)
        }
        .padding(28)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)  // the window sizes to the card
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
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4), value: appeared)
    }

    // MARK: - 2. Objective and time on it

    @ViewBuilder
    private var objectiveSection: some View {
        if currentObjective.isEmpty {
            // Nothing tracked (prompt skipped): start the day's tracking right here
            VStack(spacing: 8) {
                Text("What are you working on?")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                HStack(spacing: 6) {
                    ForEach(recentObjectives.prefix(3), id: \.self) { recent in
                        Button(recent) {
                            newObjective = recent
                            finish(.switched)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .lineLimit(1)
                    }
                    Button(recentObjectives.isEmpty ? "Set objective…" : "Something else…") {
                        mode = .switched
                        fieldFocused = true
                    }
                    .controlSize(.small)
                }
                .disabled(!buttonsEnabled)
            }
            .padding(.horizontal, 24)
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
                if let objectiveSession, ObjectiveName.same(objectiveSession.objective, currentObjective) {
                    Text("for " + objectiveSession.progressText(at: session.timestamp))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(objectiveSession.isOverEstimate(at: session.timestamp) ? .red : .orange)
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
                HStack(spacing: 8) {
                    Button {
                        finish(.onTrack)
                    } label: {
                        Label("On track", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut(.defaultAction)
                    .help("Still on your objective: back to work (Return)")

                    Button {
                        mode = .drifted
                        fieldFocused = true
                    } label: {
                        Label("Drifted", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .help("Shows your plan and lets you park what pulled you away")

                    Button {
                        mode = .switched
                        fieldFocused = true
                    } label: {
                        Label("Switched", systemImage: "arrow.left.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .help("Pick what you're working on now. Its time is tracked from here.")
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
        }
        .frame(height: 18)
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
        checkpointNumber: 3,
        objectiveSession: ObjectiveSession(
            id: UUID(), objective: "Finish the settings migration", ifThenPlan: "close the extra tabs",
            startedAt: Date().addingTimeInterval(-4800), endedAt: nil, awaySeconds: 0, awaySince: nil
        ),
        recentObjectives: ["Email", "Slides"]
    )
}
