import Foundation

@MainActor
final class ResponseLog {

    private let queue = DispatchQueue(label: "com.checkpoint.responselog")

    var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Checkpoint", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("responses.jsonl")
    }

    func append(_ session: CheckpointSession) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        guard var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        let url = fileURL
        let lineData = Data(line.utf8)
        queue.async {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(lineData)
                    handle.closeFile()
                }
            } else {
                try? lineData.write(to: url, options: .atomic)
            }
        }
    }

    func loadAll() throws -> [CheckpointSession] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let content = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return content.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(CheckpointSession.self, from: data)
        }
    }

    func deleteAll() throws {
        let url = fileURL
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
