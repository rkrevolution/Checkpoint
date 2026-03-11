import AppKit
import SwiftUI

final class CheckpointWindowController: NSWindowController {

    private var onDone: ((CheckpointSession, String?) -> Void)?
    private var onSnooze: (() -> Void)?
    private var session: CheckpointSession
    private var dismissed = false

    init(
        session: CheckpointSession,
        currentObjective: String = "",
        nextCheckpointEstimate: String = "",
        checkpointNumber: Int = 1,
        onDone: @escaping (CheckpointSession, String?) -> Void,
        onSnooze: @escaping () -> Void
    ) {
        self.session = session
        self.onDone = onDone
        self.onSnooze = onSnooze

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            styleMask: [.titled],  // no close button — you must engage
            backing: .buffered,
            defer: false
        )
        window.title = "Checkpoint"
        window.isReleasedWhenClosed = false
        window.level = .screenSaver  // above everything, even full-screen
        window.center()
        window.isMovableByWindowBackground = true

        // Blur background
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        window.contentView = visualEffect

        super.init(window: window)

        let checkpointView = CheckpointView(
            session: session,
            currentObjective: currentObjective,
            nextCheckpointEstimate: nextCheckpointEstimate,
            checkpointNumber: checkpointNumber,
            onDone: { [weak self] completed, updatedObjective in
                self?.dismissModal(with: completed, updatedObjective: updatedObjective)
            },
            onSnooze: { [weak self] in
                self?.dismissModalForSnooze()
            }
        )

        let hostingView = NSHostingView(rootView: checkpointView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func showWithFade() {
        guard let window else { return }
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 1
        }
    }

    private func dismissModal(with session: CheckpointSession, updatedObjective: String?) {
        guard !dismissed else { return }
        dismissed = true
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.close()
            self?.onDone?(session, updatedObjective)
        })
    }

    private func dismissModalForSnooze() {
        guard !dismissed else { return }
        dismissed = true
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.close()
            self?.onSnooze?()
        })
    }
}
