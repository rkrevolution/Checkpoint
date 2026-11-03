import AppKit
import SwiftUI

final class WelcomeWindowController: NSWindowController {

    private var onComplete: ((Int) -> Void)?

    init(onComplete: @escaping (Int) -> Void) {
        self.onComplete = onComplete

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = AppInfo.windowTitle("Welcome")
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        let welcomeView = WelcomeView { [weak self] interval in
            self?.window?.close()
            self?.onComplete?(interval)
        }

        window.contentView = NSHostingView(rootView: welcomeView)

        // If user closes via red X, start with default interval
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
        // Start with default interval if user closes without clicking "Start"
        let defaultInterval = UserDefaults.standard.integer(forKey: "checkpointInterval")
        onComplete?(defaultInterval > 0 ? defaultInterval : 2700)
        onComplete = nil  // prevent double-fire
    }
}
