import AppKit
import SwiftUI

/// Lightweight window that prompts user for their current objective.
/// Shown on app launch and accessible from menu bar.
final class ObjectivePromptController: NSWindowController {

    private var onDone: (() -> Void)?
    /// Called with the estimate in minutes (nil = none) just before `onDone`, when the user presses Start.
    var onEstimate: ((Int?) -> Void)?

    /// - Parameter recentObjectives: one-tap suggestions, so returning to an earlier task is quick
    ///   and its name stays consistent (time per objective only adds up when names match).
    init(recentObjectives: [String] = [], initialEstimate: Int? = nil, onDone: @escaping () -> Void) {
        self.onDone = onDone

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
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
            initialEstimate: initialEstimate,
            onSave: { [weak self] text, plan, estimate in
                if !text.isEmpty {
                    UserDefaults.standard.set(text, forKey: "currentObjective")
                }
                if plan.isEmpty {
                    UserDefaults.standard.removeObject(forKey: "currentIfThenPlan")
                } else {
                    UserDefaults.standard.set(plan, forKey: "currentIfThenPlan")
                }
                self?.onEstimate?(estimate)
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
    let initialEstimate: Int?
    var onSave: (String, String, Int?) -> Void
    var onSkip: () -> Void

    @State private var text = ""
    @State private var plan = ""
    @State private var estimate: Int?
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

            // Combo box: type a new objective, or pick a recent one from the dropdown
            HStack(spacing: 4) {
                TextField("e.g. Finishing the API integration", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
                    .focused($isFocused)
                    .onSubmit(save)
                Menu {
                    if recentObjectives.isEmpty {
                        Text("No recent objectives yet")
                    } else {
                        Section("Recent objectives") {
                            ForEach(recentObjectives, id: \.self) { recent in
                                Button(recent) { text = recent }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Pick a recent objective")
            }

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

            // Estimate (#11): guessing, then seeing the actual time, trains time sense
            HStack(spacing: 6) {
                Text("Should take about")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                ForEach([15, 30, 60, 120], id: \.self) { minutes in
                    Toggle(DurationText.short(Double(minutes) * 60), isOn: Binding(
                        get: { estimate == minutes },
                        set: { estimate = $0 ? minutes : nil }
                    ))
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
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
            estimate = initialEstimate
            isFocused = true
        }
    }

    private func save() {
        guard !trimmed(text).isEmpty else { return }
        onSave(trimmed(text), trimmed(plan), estimate)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
