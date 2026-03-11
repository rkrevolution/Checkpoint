import Foundation

struct CheckpointSession: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let intervalSeconds: Int
    let questionsShown: [Question]
    var responses: [QuestionResponse]
    var outcome: Outcome

    enum Outcome: String, Codable {
        case completed, snoozed
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, intervalSeconds
        case questionsShown = "questions"
        case responses, outcome
    }
}

struct QuestionResponse: Codable, Equatable {
    let questionId: String
    var text: String
}
