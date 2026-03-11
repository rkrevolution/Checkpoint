import AppKit
import SwiftUI

/// Brief floating toast shown when the user switches objectives.
/// Auto-dismisses after 3 seconds. Supports task-switching (EF weakness).
@MainActor
final class TransitionToast {

    private var window: NSWindow?

    func show(from oldObjective: String, to newObjective: String) {
        // Don't show if both empty or unchanged
        guard !oldObjective.isEmpty || !newObjective.isEmpty else { return }
        guard oldObjective != newObjective else { return }

        dismiss()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        let view = TransitionToastView(
            oldObjective: oldObjective,
            newObjective: newObjective
        )
        panel.contentView = NSHostingView(rootView: view)

        // Position near top-center of screen
        if let screen = NSScreen.main {
            let x = screen.frame.midX - 160
            let y = screen.frame.maxY - 120
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 1
        }

        window = panel

        // Auto-dismiss after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.dismiss()
        }
    }

    func dismiss() {
        guard let w = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            w.animator().alphaValue = 0
        }, completionHandler: {
            w.close()
        })
        window = nil
    }
}

// MARK: - SwiftUI View

private struct TransitionToastView: View {
    let oldObjective: String
    let newObjective: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                if !oldObjective.isEmpty {
                    Text(oldObjective)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .strikethrough()
                        .lineLimit(1)
                }
                if !newObjective.isEmpty {
                    Text(newObjective)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 320, height: 80)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
