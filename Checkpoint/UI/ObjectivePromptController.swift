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
    /// - Parameters:
    ///   - greeting: "Good morning" / "Welcome back" when re-entering the loop; nil for a plain change
    ///   - context: e.g. "You were on: Report · 1 h 20 min today"
    init(recentObjectives: [String] = [], initialEstimate: Int? = nil,
         greeting: String? = nil, context: String? = nil, onDone: @escaping () -> Void) {
        self.onDone = onDone

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = AppInfo.windowTitle("Objective")
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        let existing = UserDefaults.standard.string(forKey: "currentObjective") ?? ""
        let existingPlan = UserDefaults.standard.string(forKey: "currentIfThenPlan") ?? ""

        let view = ObjectivePromptView(
            initialText: existing,
            initialPlan: existingPlan,
            recentObjectives: recentObjectives.filter { !ObjectiveName.same($0, existing) },
            initialEstimate: initialEstimate,
            greeting: greeting,
            context: context,
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

        // The window follows the prompt's size (it grows when More… opens)
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = [.intrinsicContentSize]
        window.contentView = hostingView
        window.setContentSize(hostingView.fittingSize)
        window.center()

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
    let greeting: String?
    let context: String?
    var onSave: (String, String, Int?) -> Void
    var onSkip: () -> Void

    @State private var text = ""
    @State private var plan = ""
    @State private var estimate: Int?
    @AppStorage("objectivePromptShowMore") private var showMore = false
    @FocusState private var isFocused: Bool
    private let goals = Goals.current()

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

            VStack(spacing: 4) {
                if let greeting {
                    Text(greeting)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                Text("What are you working on?")
                    .font(.system(size: greeting == nil ? 16 : 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(greeting == nil ? .primary : .secondary)
                if let context {
                    Text(context)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
            }

            // Choosing what to work on is the moment goals matter most
            GoalsPanel(goals: goals)

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

            // Optional extras, tucked away so the prompt is one field at first glance
            DisclosureGroup(isExpanded: $showMore) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("If I drift, I will…")
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
                            .help("Shown on the check-in card when you answer Drifted")
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
                            .help("Your guess. Today shows how it compares with the actual time.")
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.top, 6)
            } label: {
                Text(moreLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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

    /// "More: estimate, if-then plan", or a summary of what's set, e.g. "More: ~1h · if-then plan".
    private var moreLabel: String {
        var parts: [String] = []
        if let estimate { parts.append("~" + DurationText.short(Double(estimate) * 60)) }
        if !trimmed(plan).isEmpty { parts.append("if-then plan") }
        return parts.isEmpty ? "More: estimate, if-then plan" : "More: " + parts.joined(separator: " · ")
    }

    private func save() {
        guard !trimmed(text).isEmpty else { return }
        onSave(trimmed(text), trimmed(plan), estimate)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
