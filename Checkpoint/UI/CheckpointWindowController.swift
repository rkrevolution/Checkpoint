import AppKit
import SwiftUI

final class CheckpointWindowController: NSWindowController {

    private var onDone: ((CheckpointSession, String?) -> Void)?
    private var onSnooze: (() -> Void)?
    private var session: CheckpointSession
    private var dismissed = false
    private var overlayWindows: [NSWindow] = []

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
        // Above apps, the Dock and full-screen windows — but below the screensaver
        // and lock screen, which must always win.
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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

        let fullScreen = UserDefaults.standard.bool(forKey: "fullScreenCheckpoint")
        if fullScreen {
            showOverlays()
        }

        window.alphaValue = 0
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 1
        }
    }

    // MARK: - Full-Screen Overlay

    private func showOverlays() {
        for screen in NSScreen.screens {
            let overlay = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            overlay.isReleasedWhenClosed = false
            overlay.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)  // just below the checkpoint card
            overlay.backgroundColor = .clear
            overlay.isOpaque = false
            overlay.ignoresMouseEvents = true
            overlay.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

            let blur = NSVisualEffectView(frame: screen.frame)
            blur.material = .fullScreenUI
            blur.blendingMode = .behindWindow
            blur.state = .active

            // Dark tint over the blur
            let tint = NSView(frame: screen.frame)
            tint.wantsLayer = true
            tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
            blur.addSubview(tint)

            overlay.contentView = blur
            overlay.alphaValue = 0
            overlay.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                overlay.animator().alphaValue = 1
            }

            overlayWindows.append(overlay)
        }
    }

    private func dismissOverlays(completion: @escaping () -> Void) {
        guard !overlayWindows.isEmpty else {
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            for overlay in overlayWindows {
                overlay.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            for overlay in self?.overlayWindows ?? [] {
                overlay.close()
            }
            self?.overlayWindows.removeAll()
            completion()
        })
    }

    /// Removes the card and any overlays immediately, without calling onDone/onSnooze.
    /// Used when the user goes away (sleep, lock, screensaver) mid-checkpoint.
    func dismissImmediately() {
        dismissed = true
        window?.close()
        for overlay in overlayWindows {
            overlay.close()
        }
        overlayWindows.removeAll()
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
            self?.dismissOverlays {
                self?.onDone?(session, updatedObjective)
            }
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
            self?.dismissOverlays {
                self?.onSnooze?()
            }
        })
    }
}
