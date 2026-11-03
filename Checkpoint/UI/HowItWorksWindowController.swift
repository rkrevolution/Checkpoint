import AppKit
import SwiftUI

/// The four-step loop, shared by the How It Works panel and the Welcome screen.
enum HowItWorks {
    struct Step: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let detail: String
    }

    static let steps = [
        Step(id: 1, symbol: "target", title: "Set what you're working on",
             detail: "One line, or a recent one with a tap. Optionally add how long it should take and an \"if I drift, I will…\" plan."),
        Step(id: 2, symbol: "sun.max.fill", title: "Work",
             detail: "The menu bar shows how long you've been on it. Check-ins come at unpredictable times, so you can't brace for them."),
        Step(id: 3, symbol: "checkmark.circle", title: "Answer in one tap",
             detail: "On track: back to work. Drifted: see your plan and park the distraction. Switched: pick what you're on now."),
        Step(id: 4, symbol: "calendar", title: "See your day",
             detail: "Today… in the menu shows time per objective, how your estimates compare, check-in answers and parked thoughts."),
    ]

    static let automatic = [
        "Holds check-ins during calls and shows them when you hang up",
        "Pauses while you're away (sleep, lock, screensaver) and hides from screen sharing",
        "Press ⌃⌥⌘P in any app to pause or resume",
        "Warns in the menu bar if check-ins ever stop",
    ]
}

/// One-screen explanation of the loop, with the version at the bottom (doubles as About).
final class HowItWorksWindowController: NSWindowController {

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "How Checkpoint Works"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = NSHostingView(rootView: HowItWorksView { [weak window] in window?.close() })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

private struct HowItWorksView: View {
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A tap on the shoulder for the hyperfocused. Checkpoint breaks through at unpredictable moments to show the time, how long you've been on what you meant to do, and one question.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(HowItWorks.steps) { step in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: step.symbol)
                            .font(.system(size: 16))
                            .foregroundStyle(.orange)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(step.id). \(step.title)")
                                .font(.system(size: 13, weight: .semibold))
                            Text(step.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("AUTOMATICALLY")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(HowItWorks.automatic, id: \.self) { line in
                    Label(line, systemImage: "checkmark")
                        .font(.system(size: 12))
                        .labelStyle(.titleAndIcon)
                }
            }

            HStack {
                Text(AppInfo.displayString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
