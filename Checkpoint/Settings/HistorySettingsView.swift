import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HistorySettingsView: View {
    @State private var sessions: [CheckpointSession] = []
    @State private var filterOutcome: CheckpointSession.Outcome?
    @State private var showingClearConfirmation = false
    @State private var errorMessage: String?

    @AppStorage("logResponses") private var logResponses = true

    private let responseLog = ResponseLog()
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var filteredSessions: [CheckpointSession] {
        let sorted = sessions.sorted { $0.timestamp > $1.timestamp }
        if let filter = filterOutcome {
            return sorted.filter { $0.outcome == filter }
        }
        return sorted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Controls
            HStack {
                Toggle("Log responses", isOn: $logResponses)

                Spacer()

                Picker("Filter", selection: $filterOutcome) {
                    Text("All").tag(nil as CheckpointSession.Outcome?)
                    Text("Completed").tag(CheckpointSession.Outcome.completed as CheckpointSession.Outcome?)
                    Text("Snoozed").tag(CheckpointSession.Outcome.snoozed as CheckpointSession.Outcome?)
                }
                .frame(width: 150)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Session list
            if filteredSessions.isEmpty {
                VStack {
                    Spacer()
                    Text("No checkpoint history yet.")
                        .foregroundStyle(.secondary)
                    Text("Sessions will appear here after your first check-in.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                // Keyed by position: older logs can contain the same session ID more than once
                List(Array(filteredSessions.enumerated()), id: \.offset) { _, session in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(dateFormatter.string(from: session.timestamp))
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(outcomeLabel(session.outcome))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(outcomeColor(session.outcome).opacity(0.15), in: Capsule())
                                .foregroundStyle(outcomeColor(session.outcome))
                        }

                        ForEach(Array(zip(session.questionsShown, session.responses)), id: \.0.id) { question, response in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(question.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !response.text.isEmpty {
                                    Text(response.text)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Export JSON") {
                    exportJSON()
                }

                Button("Export CSV") {
                    exportCSV()
                }

                Spacer()

                Button("Clear History") {
                    showingClearConfirmation = true
                }
                .foregroundStyle(.red)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            do {
                sessions = try responseLog.loadAll()
            } catch {
                errorMessage = "Couldn't load history: \(error.localizedDescription)"
            }
        }
        .alert("Clear All History?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                do {
                    try responseLog.deleteAll()
                    sessions = []
                } catch {
                    errorMessage = "Couldn't clear history: \(error.localizedDescription)"
                }
            }
        } message: {
            Text("This will permanently delete all checkpoint history. This cannot be undone.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func outcomeLabel(_ outcome: CheckpointSession.Outcome) -> String {
        switch outcome {
        case .completed: return "Completed"
        case .snoozed: return "Snoozed"
        }
    }

    private func outcomeColor(_ outcome: CheckpointSession.Outcome) -> Color {
        switch outcome {
        case .completed: return .green
        case .snoozed: return .blue
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "checkpoint-history.json"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                try encoder.encode(sessions).write(to: url, options: .atomic)
            } catch {
                errorMessage = "Couldn't export JSON: \(error.localizedDescription)"
            }
        }
    }

    /// Quotes a CSV field per RFC 4180 (embedded quotes doubled; commas and newlines kept inside quotes).
    nonisolated static func csvField(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // For previews: inject sample data
    init(previewSessions: [CheckpointSession]? = nil) {
        if let previewSessions {
            _sessions = State(initialValue: previewSessions)
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "checkpoint-history.csv"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let formatter = ISO8601DateFormatter()
            var csv = "timestamp,outcome,questions,responses\n"
            for session in sessions {
                let fields = [
                    formatter.string(from: session.timestamp),
                    session.outcome.rawValue,
                    session.questionsShown.map(\.text).joined(separator: "; "),
                    session.responses.map(\.text).joined(separator: "; "),
                ]
                csv += fields.map(Self.csvField).joined(separator: ",") + "\n"
            }
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                errorMessage = "Couldn't export CSV: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    let sampleSessions: [CheckpointSession] = [
        CheckpointSession(
            id: UUID(),
            timestamp: Date(),
            intervalSeconds: 2700,
            questionsShown: [Question(id: "q1", text: "What were you doing just before this appeared?", isEnabled: true, isCustom: false, categoryId: "awareness")],
            responses: [QuestionResponse(questionId: "q1", text: "")],
            outcome: .completed
        ),
        CheckpointSession(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-3600),
            intervalSeconds: 2700,
            questionsShown: [Question(id: "q2", text: "Are you still working on what you intended?", isEnabled: true, isCustom: false, categoryId: "focus")],
            responses: [QuestionResponse(questionId: "q2", text: "")],
            outcome: .snoozed
        ),
        CheckpointSession(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-7200),
            intervalSeconds: 1800,
            questionsShown: [Question(id: "q3", text: "When did you last stand up or stretch?", isEnabled: true, isCustom: false, categoryId: "body")],
            responses: [QuestionResponse(questionId: "q3", text: "")],
            outcome: .completed
        ),
    ]
    HistorySettingsView(previewSessions: sampleSessions)
        .frame(width: 520, height: 480)
}
