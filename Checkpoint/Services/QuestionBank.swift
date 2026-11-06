import Foundation

@MainActor
final class QuestionBank {

    var customStore: CustomQuestionStore?

    private(set) var bundledCategories: [Category] = []
    private(set) var bundledQuestions: [Question] = []

    var allBundledQuestions: [Question] { bundledQuestions }

    private let settings: AppSettings

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        loadBundled()
    }

    func selectQuestions(count: Int, recentCategoryIds: [String] = []) -> [Question] {
        let allQuestions = enabledQuestions()
        guard !allQuestions.isEmpty else { return [] }

        let requestedCount = min(count, allQuestions.count)

        // Group by category
        var byCategory: [String: [Question]] = [:]
        for q in allQuestions {
            byCategory[q.categoryId, default: []].append(q)
        }

        // Favor categories not recently shown
        let categoryIds = Array(byCategory.keys)
        let nonRecent = categoryIds.filter { !recentCategoryIds.contains($0) }
        let preferred = nonRecent.isEmpty ? categoryIds : nonRecent

        var selected: [Question] = []
        var usedCategories = Set<String>()
        var shuffledPreferred = preferred.shuffled()

        // Pick one question per category first for diversity
        while selected.count < requestedCount, !shuffledPreferred.isEmpty {
            let catId = shuffledPreferred.removeFirst()
            guard !usedCategories.contains(catId),
                  let candidates = byCategory[catId]?.filter({ q in !selected.contains(where: { $0.id == q.id }) }),
                  let pick = candidates.randomElement() else { continue }
            selected.append(pick)
            usedCategories.insert(catId)
        }

        // If still need more, pick from remaining
        if selected.count < requestedCount {
            let remaining = allQuestions.filter { q in !selected.contains(where: { $0.id == q.id }) }.shuffled()
            selected.append(contentsOf: remaining.prefix(requestedCount - selected.count))
        }

        return selected
    }

    func reload() {
        loadBundled()
    }

    // MARK: - Private

    private func enabledQuestions() -> [Question] {
        let disabled = settings.disabledQuestionIDs
        var questions = bundledQuestions.filter { !disabled.contains($0.id) }

        // Merge custom questions
        if let store = customStore {
            let enabledCustom = store.customQuestions.filter { $0.isEnabled }
            questions.append(contentsOf: enabledCustom)
        }

        // Filter out questions whose category is disabled
        let disabledCategories = allCategories().filter { !$0.isEnabled }.map(\.id)
        questions = questions.filter { !disabledCategories.contains($0.categoryId) }

        return questions
    }

    private func allCategories() -> [Category] {
        var cats = bundledCategories
        if let store = customStore {
            cats.append(contentsOf: store.customCategories)
        }
        return cats
    }

    private func loadBundled() {
        guard let url = Bundle.main.url(forResource: "questions", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            loadHardcodedFallback()
            return
        }
        do {
            let bank = try JSONDecoder().decode(BundledBank.self, from: data)
            bundledCategories = bank.categories.map {
                Category(id: $0.id, name: $0.name, isEnabled: true, isCustom: false)
            }
            bundledQuestions = bank.categories.flatMap { cat in
                cat.questions.map {
                    Question(id: $0.id, text: $0.text, isEnabled: true, isCustom: false, categoryId: cat.id)
                }
            }
        } catch {
            loadHardcodedFallback()
        }
    }

    private func loadHardcodedFallback() {
        bundledCategories = [
            Category(id: "alignment", name: "Alignment & Priority", isEnabled: true, isCustom: false),
            Category(id: "scope", name: "Scope & Depth", isEnabled: true, isCustom: false),
            Category(id: "progress", name: "Progress", isEnabled: true, isCustom: false),
            Category(id: "time", name: "Time Awareness", isEnabled: true, isCustom: false),
            Category(id: "body", name: "Body & Energy", isEnabled: true, isCustom: false),
            Category(id: "mindfulness", name: "Mindfulness & Reset", isEnabled: true, isCustom: false),
        ]
        bundledQuestions = [
            Question(id: "a1", text: "Is this still the best use of my time right now?", isEnabled: true, isCustom: false, categoryId: "alignment"),
            Question(id: "a2", text: "What am I actually trying to accomplish with this task?", isEnabled: true, isCustom: false, categoryId: "alignment"),
            Question(id: "b1", text: "Is it still reasonable for me to be spending time here?", isEnabled: true, isCustom: false, categoryId: "scope"),
            Question(id: "b5", text: "Is this more detailed than the situation calls for?", isEnabled: true, isCustom: false, categoryId: "scope"),
            Question(id: "d3", text: "Do I still have a clear picture of what I'm working toward?", isEnabled: true, isCustom: false, categoryId: "time"),
            Question(id: "h1", text: "Have I eaten, hydrated, or stretched recently?", isEnabled: true, isCustom: false, categoryId: "body"),
            Question(id: "f1", text: "Would stepping away for a moment help right now?", isEnabled: true, isCustom: false, categoryId: "mindfulness"),
            Question(id: "f3", text: "What's one thing I'd want to have done by the next checkpoint?", isEnabled: true, isCustom: false, categoryId: "mindfulness"),
        ]
    }
}

// MARK: - JSON Decoding Types

private struct BundledBank: Codable {
    let version: Int
    let categories: [BundledCategory]
}

private struct BundledCategory: Codable {
    let id: String
    let name: String
    let questions: [BundledQuestion]
}

private struct BundledQuestion: Codable {
    let id: String
    let text: String
}
