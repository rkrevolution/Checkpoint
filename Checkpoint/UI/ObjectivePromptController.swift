import AppKit
import SwiftUI

/// Lightweight window that prompts user for their current objective.
/// Shown on app launch and accessible from menu bar.
final class ObjectivePromptController: NSWindowController {

    private var onDone: (() -> Void)?

    /// - Parameter recentObjectives: one-tap suggestions, so returning to an earlier task is quick
    ///   and its name stays consistent (time per objective only adds up when names match).
    init(recentObjectives: [String] = [], onDone: @escaping () -> Void) {
        self.onDone = onDone

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Checkpoint"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        let existing = UserDefaults.standard.string(forKey: "currentObjective") ?? ""
        let existingPlan = UserDefaults.standard.string(forKey: "currentIfThenPlan") ?? ""

        let view = ObjectivePromptView(
            initialText: existing,
            initialPlan: existingPlan,
            recentObjectives: recentObjectives.filter { $0 != existing },
            onSave: { [weak self] text, plan in
                if !text.isEmpty {
                    UserDefaults.standard.set(text, forKey: "currentObjective")
                }
                if plan.isEmpty {
                    UserDefaults.standard.removeObject(forKey: "currentIfThenPlan")
                } else {
                    UserDefaults.standard.set(plan, forKey: "currentIfThenPlan")
                }
                self?.window?.close()
                self?.onDone?()
                self?.onDone = nil
            },
            onSkip: { [weak self] in
                self?.window?.close()
                self?.onDone?()
                self?.onDone = nil
            }
        )

        window.contentView = NSHostingView(rootView: view)

        // Handle red X close
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        onDone?()
        onDone = nil
    }
}

// MARK: - SwiftUI View

private struct ObjectivePromptView: View {
    let initialText: String
    let initialPlan: String
    let recentObjectives: [String]
    var onSave: (String, String) -> Void
    var onSkip: () -> Void

    @State private var text = ""
    @State private var plan = ""
    @FocusState private var isFocused: Bool

    /// Common if-then plans, from "distractibility delay" and re-orienting strategies.
    private let planSuggestions = [
        "write the distraction down and come back",
        "re-read my objective and do the next small step",
        "close the extra tabs and apps",
        "stand up, stretch, then restart",
    ]

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            Text("What are you working on?")
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            TextField("e.g. Finishing the API integration", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .focused($isFocused)
                .onSubmit(save)

            if !recentObjectives.isEmpty {
                HStack(spacing: 6) {
                    Text("Recent:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ForEach(recentObjectives.prefix(3), id: \.self) { recent in
                        Button(recent) { text = recent }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("If I drift, I will… (optional)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu("Suggestions") {
                        ForEach(planSuggestions, id: \.self) { suggestion in
                            Button(suggestion) { plan = suggestion }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .fixedSize()
                }
                TextField("e.g. write the distraction down and come back", text: $plan)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(save)
            }

            HStack {
                Button("Skip") {
                    onSkip()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

                Spacer()

                Button {
                    save()
                } label: {
                    Text("Start")
                        .font(.system(size: 13, weight: .medium))
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(trimmed(text).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            text = initialText
            plan = initialPlan
            isFocused = true
        }
    }

    private func save() {
        guard !trimmed(text).isEmpty else { return }
        onSave(trimmed(text), trimmed(plan))
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
