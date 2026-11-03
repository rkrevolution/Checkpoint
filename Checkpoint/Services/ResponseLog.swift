import Foundation

/// Checkpoint history (`responses.jsonl`).
@MainActor
final class ResponseLog {

    private let file = JSONLinesFile<CheckpointSession>(url: JSONLinesFile<CheckpointSession>.appSupportURL("responses.jsonl"))

    var fileURL: URL { file.url }

    func append(_ session: CheckpointSession) throws {
        file.append(session)
    }

    func loadAll() throws -> [CheckpointSession] {
        try file.loadAll()
    }

    func deleteAll() throws {
        try file.deleteAll()
    }
}
