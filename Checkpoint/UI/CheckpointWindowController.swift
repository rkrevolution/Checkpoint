import AppKit
import os.log
import SwiftUI

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "CheckpointWindowController")

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
        objectiveSession: ObjectiveSession? = nil,
        recentObjectives: [String] = [],
        allowSnooze: Bool = true,
        onDone: @escaping (CheckpointSession, String?) -> Void,
        onSnooze: @escaping () -> Void
    ) {
        self.session = session
        self.onDone = onDone
        self.onSnooze = onSnooze

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 440),
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
        // Keep the card (and your objective) out of screen shares and recordings (#1)
        window.sharingType = .none
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
            objectiveSession: objectiveSession,
            recentObjectives: recentObjectives,
            allowSnooze: allowSnooze,
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
            overlay.sharingType = .none
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
        let overlays = overlayWindows
        animate(duration: 0.2, { _ in
            for overlay in overlays {
                overlay.animator().alphaValue = 0
            }
        }, completion: { [weak self] in
            for overlay in overlays {
                overlay.close()
            }
            self?.overlayWindows.removeAll()
            completion()
        })
    }

    /// Runs an animation, then `completion` exactly once: when the animation ends, or shortly
    /// after its duration if AppKit never calls the completion handler. A missed callback must
    /// never leave the app stuck presenting a checkpoint.
    private func animate(
        duration: TimeInterval,
        _ animations: @escaping (NSAnimationContext) -> Void,
        completion: @escaping () -> Void
    ) {
        let once = RunOnce(completion)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            animations(context)
        }, completionHandler: {
            MainActor.assumeIsolated { once.run() }
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) {
            once.run()
        }
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

    #if DEBUG
    /// Same as pressing "Got it" / "Not now" (used by the e2e test script).
    func debugAcknowledge() { dismissModal(with: session, updatedObjective: nil) }
    func debugSnooze() { dismissModalForSnooze() }
    #endif

    private func dismissModal(with session: CheckpointSession, updatedObjective: String?) {
        fadeOutAndClose { [weak self] in
            self?.onDone?(session, updatedObjective)
        }
    }

    private func dismissModalForSnooze() {
        fadeOutAndClose { [weak self] in
            self?.onSnooze?()
        }
    }

    private func fadeOutAndClose(then action: @escaping () -> Void) {
        log.notice("fadeOutAndClose: dismissed=\(self.dismissed)")
        guard !dismissed, let window else { return }
        dismissed = true
        animate(duration: 0.2, { _ in
            window.animator().alphaValue = 0
        }, completion: { [weak self] in
            window.close()
            self?.dismissOverlays(completion: action)
        })
    }
}

/// Calls a closure at most once, however many times `run()` is called.
private final class RunOnce {
    private var action: (() -> Void)?

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func run() {
        let pending = action
        action = nil
        pending?()
    }
}
