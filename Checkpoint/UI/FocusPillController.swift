import AppKit
import Combine
import SwiftUI

/// When the always-visible focus pill should be on screen.
enum FocusPillPolicy {
    nonisolated static func shouldShow(enabled: Bool, hasObjective: Bool, isPaused: Bool, isAway: Bool) -> Bool {
        enabled && hasObjective && !isPaused && !isAway
    }
}

/// A small floating strip showing the current objective and time on it, in the same style as
/// the objective-switch toast. Keeps the goal in view (working memory) without taking focus.
/// Draggable, remembers its position, hidden from screen sharing (see `ScreenCapturePrivacy`); ✕ turns it off.
@MainActor
final class FocusPillController {

    private var panel: NSPanel?
    private let tracker: ObjectiveTracker
    private let onChangeObjective: () -> Void
    private static let size = NSSize(width: 340, height: 54)
    private var captureSetting: AnyCancellable?

    init(tracker: ObjectiveTracker, onChangeObjective: @escaping () -> Void) {
        self.tracker = tracker
        self.onChangeObjective = onChangeObjective
        // The strip stays open for hours, so follow the screen-capture setting while it's up
        captureSetting = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in ScreenCapturePrivacy.isHidden() }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let panel = self?.panel else { return }
                    ScreenCapturePrivacy.apply(to: panel)
                }
            }
    }

    private weak var appState: AppState?
    private var isAway: () -> Bool = { false }
    private var visibility: AnyCancellable?

    /// Keeps the strip in step with its setting, the objective and pause. Away isn't published,
    /// so call `refresh()` when it changes.
    func follow(appState: AppState, isAway: @escaping () -> Bool) {
        self.appState = appState
        self.isAway = isAway
        visibility = tracker.$current.map { $0 == nil }.removeDuplicates()
            .combineLatest(appState.$state.map { $0 == .paused }.removeDuplicates(),
                           UserDefaults.standard.publisher(for: \.showFocusPill).removeDuplicates())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        guard let appState else { return }
        setVisible(FocusPillPolicy.shouldShow(
            enabled: AppSettings().showFocusPill,
            hasObjective: tracker.current != nil,
            isPaused: appState.state == .paused,
            isAway: isAway()
        ))
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            show()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func show() {
        if panel == nil { panel = makePanel() }
        panel?.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        ScreenCapturePrivacy.apply(to: panel)

        let view = FocusPillView(
            onChange: { [weak self] in self?.onChangeObjective() },
            onClose: { AppSettings().showFocusPill = false }
        )
        .environmentObject(tracker)
        panel.contentView = NSHostingView(rootView: view)

        // Remember where the user puts it; default to top-center, just under the menu bar
        if !panel.setFrameUsingName("FocusPill"), let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - Self.size.width / 2,
                y: screen.visibleFrame.maxY - Self.size.height - 8))
        }
        panel.setFrameAutosaveName("FocusPill")
        return panel
    }
}

private struct FocusPillView: View {
    var onChange: () -> Void
    var onClose: () -> Void

    @EnvironmentObject private var tracker: ObjectiveTracker

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 10) {
                Image(systemName: "target")
                    .font(.system(size: 16))
                    .foregroundStyle(.orange)

                if let session = tracker.current {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.objective)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Text(timeText(session, at: context.date))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(session.isOverEstimate(at: context.date) ? .red : .secondary)
                    }
                }

                Spacer(minLength: 4)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Hide (turn it back on from the menu: Show Focus)")
            }
            .padding(.horizontal, 14)
            .frame(width: 340, height: 54)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onChange)
            .help("Your current focus. Double-click to change it; drag to move.")
        }
    }

    private func timeText(_ session: ObjectiveSession, at now: Date) -> String {
        let active = DurationText.long(session.activeSeconds(at: now))
        if let minutes = session.estimateMinutes {
            return "\(active) of ~\(DurationText.long(Double(minutes) * 60))"
        }
        return active
    }
}
