import Foundation
import os.log

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "JSONLinesFile")
private let jsonLinesQueue = DispatchQueue(label: "com.checkpoint.jsonlines")

extension JSONEncoder {
    nonisolated static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    nonisolated static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// An append-only file of one JSON value per line (used for history and objective sessions).
final class JSONLinesFile<Element: Codable> {

    let url: URL
    /// Shared by all instances so a read through any instance waits for every pending write.
    private var queue: DispatchQueue { jsonLinesQueue }

    init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/Checkpoint/<name>`
    nonisolated static func appSupportURL(_ name: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Checkpoint", isDirectory: true)
        return dir.appendingPathComponent(name)
    }

    /// Appends asynchronously; failures are logged (never thrown into the UI path).
    func append(_ element: Element) {
        guard var line = (try? JSONEncoder.iso8601.encode(element)).flatMap({ String(data: $0, encoding: .utf8) }) else {
            log.error("Failed to encode entry for \(self.url.lastPathComponent, privacy: .public)")
            return
        }
        line += "\n"
        let url = self.url
        let lineData = Data(line.utf8)
        queue.async {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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
                log.error("Failed to append to \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Waits for pending appends, then reads every decodable line (bad lines are skipped).
    func loadAll() throws -> [Element] {
        queue.sync {}
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let content = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder.iso8601
        return content.split(separator: "\n").compactMap { line in
            try? decoder.decode(Element.self, from: Data(line.utf8))
        }
    }

    func deleteAll() throws {
        queue.sync {}
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
