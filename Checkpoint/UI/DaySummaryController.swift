import AppKit
import SwiftUI

/// Shows a brief end-of-day summary when active hours end.
/// "Today: N checkpoints, worked on: X, Y, Z"
final class DaySummaryController: NSWindowController {

    init(checkpointCount: Int, objectiveTimes: [(objective: String, seconds: TimeInterval)]) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Day Summary"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        super.init(window: window)

        let view = DaySummaryView(
            checkpointCount: checkpointCount,
            objectiveTimes: objectiveTimes,
            onDismiss: { [weak self] in
                self?.window?.close()
            }
        )
        window.contentView = NSHostingView(rootView: view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SwiftUI View

private struct DaySummaryView: View {
    let checkpointCount: Int
    let objectiveTimes: [(objective: String, seconds: TimeInterval)]
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            Text("End of active hours")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            VStack(spacing: 6) {
                Text("\(checkpointCount) checkpoint\(checkpointCount == 1 ? "" : "s") today")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)

                if !objectiveTimes.isEmpty {
                    Text("Worked on: " + objectiveTimes.map { item in
                        item.seconds >= 60 ? "\(item.objective) (\(DurationText.long(item.seconds)))" : item.objective
                    }.joined(separator: ", "))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }

            Button("Done") {
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 340, height: 200)
    }
}
