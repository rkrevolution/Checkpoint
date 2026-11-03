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
