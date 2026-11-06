import Foundation

struct CheckpointSession: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let intervalSeconds: Int
    let questionsShown: [Question]
    var responses: [QuestionResponse]
    var outcome: Outcome
    /// The user's one-tap answer to "Right now I'm…" (#12). Nil for snoozes and older entries.
    var checkInResponse: CheckInResponse? = nil
    /// A distraction written down on the card (#34).
    var parkedThought: String? = nil

    enum Outcome: String, Codable {
        case completed, snoozed
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, intervalSeconds
        case questionsShown = "questions"
        case responses, outcome, checkInResponse, parkedThought
    }
}

/// One-tap answer on the checkpoint card.
enum CheckInResponse: String, Codable, CaseIterable {
    case onTrack, drifted, switched

    var label: String {
        switch self {
        case .onTrack: return "On track"
        case .drifted: return "Drifted"
        case .switched: return "Switched"
        }
    }
}

struct QuestionResponse: Codable, Equatable {
    let questionId: String
    var text: String
}

extension CheckpointSession {
    /// A new, unanswered check-in showing `questions`.
    init(questions: [Question], at timestamp: Date = Date(), intervalSeconds: Int = 0) {
        self.init(
            id: UUID(),
            timestamp: timestamp,
            intervalSeconds: intervalSeconds,
            questionsShown: questions,
            responses: questions.map { QuestionResponse(questionId: $0.id, text: "") },
            outcome: .completed
        )
    }

    /// The same check-in as it's shown at `time`, `elapsed` seconds after the last one ended
    /// (also when it comes back after a snooze).
    func shown(at time: Date, elapsed: Int) -> CheckpointSession {
        var copy = CheckpointSession(
            id: id, timestamp: time, intervalSeconds: elapsed,
            questionsShown: questionsShown, responses: responses, outcome: outcome)
        copy.checkInResponse = checkInResponse
        copy.parkedThought = parkedThought
        return copy
    }

    /// The History entry for a "Not now": its own id, so History never sees duplicates.
    func snoozedEntry(at time: Date) -> CheckpointSession {
        CheckpointSession(
            id: UUID(), timestamp: time, intervalSeconds: intervalSeconds,
            questionsShown: questionsShown, responses: responses, outcome: .snoozed)
    }
}
