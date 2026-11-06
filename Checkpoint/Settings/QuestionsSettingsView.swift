import SwiftUI

struct QuestionsSettingsView: View {
    @EnvironmentObject private var customStore: CustomQuestionStore

    @State private var selectedCategoryId: String? = "alignment"
    @State private var showingAddQuestion = false
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var newQuestionText = ""
    @State private var newQuestionCategoryId = ""

    private var disabledQuestionIDs: Set<String> {
        AppSettings().disabledQuestionIDs
    }

    private func toggleQuestion(_ id: String, enabled: Bool) {
        let settings = AppSettings()
        if enabled {
            settings.disabledQuestionIDs.remove(id)
        } else {
            settings.disabledQuestionIDs.insert(id)
        }
    }

    // All categories: built-in + custom
    private var allCategories: [Category] {
        let builtIn: [Category] = [
            Category(id: "alignment", name: "Alignment & Priority", isEnabled: true, isCustom: false),
            Category(id: "scope", name: "Scope & Depth", isEnabled: true, isCustom: false),
            Category(id: "progress", name: "Progress", isEnabled: true, isCustom: false),
            Category(id: "time", name: "Time Awareness", isEnabled: true, isCustom: false),
            Category(id: "body", name: "Body & Energy", isEnabled: true, isCustom: false),
            Category(id: "mindfulness", name: "Mindfulness & Reset", isEnabled: true, isCustom: false),
        ]
        return builtIn + customStore.customCategories
    }

    private var builtInQuestions: [Question] {
        QuestionBank().allBundledQuestions
    }

    private func questionsForCategory(_ categoryId: String) -> [Question] {
        let bundled = builtInQuestions.filter { $0.categoryId == categoryId }
        let custom = customStore.customQuestions.filter { $0.categoryId == categoryId }
        return bundled + custom
    }

    var body: some View {
        HSplitView {
            // Category sidebar
            VStack(alignment: .leading, spacing: 0) {
                List(allCategories, selection: $selectedCategoryId) { category in
                    HStack {
                        Text(category.name)
                            .font(.body)
                        Spacer()
                        let count = questionsForCategory(category.id).count
                        Text("\(count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(category.id)
                    .contextMenu {
                        if category.isCustom {
                            Button("Delete") {
                                customStore.deleteCategory(id: category.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()

                Button {
                    showingAddCategory = true
                    newCategoryName = ""
                } label: {
                    Label("New Category", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(minWidth: 180, maxWidth: 200)

            // Question list
            VStack(alignment: .leading, spacing: 0) {
                if let catId = selectedCategoryId {
                    let questions = questionsForCategory(catId)

                    List {
                        ForEach(questions) { question in
                            HStack {
                                let isEnabled = !disabledQuestionIDs.contains(question.id)
                                Toggle("", isOn: Binding(
                                    get: { isEnabled },
                                    set: { toggleQuestion(question.id, enabled: $0) }
                                ))
                                .toggleStyle(.switch)
                                .labelsHidden()

                                Text(question.text)
                                    .font(.body)
                                    .opacity(isEnabled ? 1.0 : 0.4)

                                Spacer()

                                if question.isCustom {
                                    Button {
                                        customStore.deleteQuestion(id: question.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Divider()

                    Button {
                        newQuestionText = ""
                        newQuestionCategoryId = catId
                        showingAddQuestion = true
                    } label: {
                        Label("Add Question", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .padding(8)
                } else {
                    VStack {
                        Spacer()
                        Text("Select a category")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(minWidth: 280)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingAddQuestion) {
            addQuestionSheet
        }
        .sheet(isPresented: $showingAddCategory) {
            addCategorySheet
        }
    }

    // MARK: - Add Question Sheet

    private var addQuestionSheet: some View {
        VStack(spacing: 16) {
            Text("Add Question")
                .font(.headline)

            TextField("Question text", text: $newQuestionText, axis: .vertical)
                .lineLimit(3...5)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("\(newQuestionText.count)/200")
                    .font(.caption)
                    .foregroundStyle(newQuestionText.count > 200 ? .red : .secondary)
                Spacer()
            }

            HStack {
                Button("Cancel") {
                    showingAddQuestion = false
                }
                Spacer()
                Button("Save") {
                    let q = Question(
                        id: "cq-\(UUID().uuidString.prefix(8))",
                        text: newQuestionText.trimmingCharacters(in: .whitespacesAndNewlines),
                        isEnabled: true,
                        isCustom: true,
                        categoryId: newQuestionCategoryId
                    )
                    customStore.addQuestion(q)
                    showingAddQuestion = false
                }
                .disabled(newQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newQuestionText.count > 200)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    // MARK: - Add Category Sheet

    private var addCategorySheet: some View {
        VStack(spacing: 16) {
            Text("New Category")
                .font(.headline)

            TextField("Category name", text: $newCategoryName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    showingAddCategory = false
                }
                Spacer()
                Button("Create") {
                    let cat = Category(
                        id: "cat-\(UUID().uuidString.prefix(8))",
                        name: newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines),
                        isEnabled: true,
                        isCustom: true
                    )
                    customStore.addCategory(cat)
                    selectedCategoryId = cat.id
                    showingAddCategory = false
                }
                .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}
