import Combine
import Foundation

/// A distraction written down to deal with later ("distractibility delay", #34).
nonisolated struct ParkedThought: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    let createdAt: Date
    /// What the user was working on when they parked it.
    let objective: String?
}

/// Parked thoughts, appended to `parked.jsonl`; "done" is tracked by ID in `defaults`.
@MainActor
final class ParkedThoughts: ObservableObject {

    @Published private(set) var open: [ParkedThought] = []

    private let file: JSONLinesFile<ParkedThought>
    private let defaults: UserDefaults
    private static let doneKey = "parkedThoughtsDone"

    init(defaults: UserDefaults = .standard,
         url: URL = JSONLinesFile<ParkedThought>.appSupportURL("parked.jsonl")) {
        self.defaults = defaults
        self.file = JSONLinesFile(url: url)
        reload()
    }

    func park(_ text: String, objective: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let thought = ParkedThought(id: UUID(), text: trimmed, createdAt: Date(), objective: objective)
        file.append(thought)
        open.append(thought)
    }

    func markDone(_ id: UUID) {
        var done = Set(defaults.stringArray(forKey: Self.doneKey) ?? [])
        done.insert(id.uuidString)
        defaults.set(Array(done), forKey: Self.doneKey)
        open.removeAll { $0.id == id }
    }

    private func reload() {
        let done = Set(defaults.stringArray(forKey: Self.doneKey) ?? [])
        open = ((try? file.loadAll()) ?? []).filter { !done.contains($0.id.uuidString) }
    }
}
