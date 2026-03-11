import Combine
import Foundation

@MainActor
final class CustomQuestionStore: ObservableObject {
    @Published var customCategories: [Category] = []
    @Published var customQuestions: [Question] = []

    init() {
        load()
    }

    func addQuestion(_ question: Question) {
        customQuestions.append(question)
        save()
    }

    func updateQuestion(_ question: Question) {
        if let idx = customQuestions.firstIndex(where: { $0.id == question.id }) {
            customQuestions[idx] = question
            save()
        }
    }

    func deleteQuestion(id: String) {
        customQuestions.removeAll { $0.id == id }
        save()
    }

    func addCategory(_ category: Category) {
        customCategories.append(category)
        save()
    }

    func renameCategory(id: String, newName: String) {
        if let idx = customCategories.firstIndex(where: { $0.id == id }) {
            let old = customCategories[idx]
            customCategories[idx] = Category(id: old.id, name: newName, isEnabled: old.isEnabled, isCustom: true)
            save()
        }
    }

    func deleteCategory(id: String) {
        customCategories.removeAll { $0.id == id }
        customQuestions.removeAll { $0.categoryId == id }
        save()
    }

    func exportJSON() throws -> Data {
        let export = CustomExport(
            exportVersion: 1,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            customCategories: customCategories.map { ExportCategory(id: $0.id, name: $0.name) },
            customQuestions: customQuestions.map { ExportQuestion(id: $0.id, categoryId: $0.categoryId, text: $0.text, enabled: $0.isEnabled) }
        )
        return try JSONEncoder().encode(export)
    }

    func importJSON(_ data: Data) throws {
        let decoded = try JSONDecoder().decode(CustomExport.self, from: data)
        customCategories = decoded.customCategories.map {
            Category(id: $0.id, name: $0.name, isEnabled: true, isCustom: true)
        }
        customQuestions = decoded.customQuestions.map {
            Question(id: $0.id, text: $0.text, isEnabled: $0.enabled, isCustom: true, categoryId: $0.categoryId)
        }
        save()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(customCategories) {
            UserDefaults.standard.set(data, forKey: "customCategoriesData")
        }
        if let data = try? JSONEncoder().encode(customQuestions) {
            UserDefaults.standard.set(data, forKey: "customQuestionsData")
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: "customCategoriesData"),
           let cats = try? JSONDecoder().decode([Category].self, from: data) {
            customCategories = cats
        }
        if let data = UserDefaults.standard.data(forKey: "customQuestionsData"),
           let qs = try? JSONDecoder().decode([Question].self, from: data) {
            customQuestions = qs
        }
    }
}

// MARK: - Export Types

private struct CustomExport: Codable {
    let exportVersion: Int
    let exportedAt: String
    let customCategories: [ExportCategory]
    let customQuestions: [ExportQuestion]
}

private struct ExportCategory: Codable {
    let id: String
    let name: String
}

private struct ExportQuestion: Codable {
    let id: String
    let categoryId: String
    let text: String
    let enabled: Bool
}
