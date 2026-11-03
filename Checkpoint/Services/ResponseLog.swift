import Foundation
import os.log

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "ResponseLog")

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
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    // Throwing FileHandle APIs: the legacy write(_:) raises an ObjC exception on I/O failure
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: lineData)
                } else {
                    try lineData.write(to: url, options: .atomic)
                }
            } catch {
                log.error("Failed to append to response log: \(error.localizedDescription, privacy: .public)")
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
