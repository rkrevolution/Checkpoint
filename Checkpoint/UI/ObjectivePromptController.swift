import AppKit
import SwiftUI

/// Lightweight window that prompts user for their current objective.
/// Shown on app launch and accessible from menu bar.
final class ObjectivePromptController: NSWindowController {

    private var onDone: (() -> Void)?

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Checkpoint"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        let existing = UserDefaults.standard.string(forKey: "currentObjective") ?? ""

        let view = ObjectivePromptView(
            initialText: existing,
            onSave: { [weak self] text in
                if !text.isEmpty {
                    UserDefaults.standard.set(text, forKey: "currentObjective")
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
    var onSave: (String) -> Void
    var onSkip: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            Text("What are you working on?")
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            TextField("e.g. Finishing the API integration", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .focused($isFocused)
                .onSubmit {
                    onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
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
                    onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: {
                    Text("Start")
                        .font(.system(size: 13, weight: .medium))
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380, height: 180)
        .onAppear {
            text = initialText
            isFocused = true
        }
    }
}
