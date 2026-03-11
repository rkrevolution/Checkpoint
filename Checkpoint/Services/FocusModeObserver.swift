import Foundation

@MainActor
final class FocusModeObserver: NSObject {

    var onFocusChanged: ((Bool) -> Void)?
    private(set) var isFocusActive: Bool = false

    func startObserving() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(dndDidChange),
            name: NSNotification.Name("com.apple.notificationcenterui.dndstart"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(dndDidChange),
            name: NSNotification.Name("com.apple.notificationcenterui.dndend"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    func stopObserving() {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc nonisolated private func dndDidChange(_ note: Notification) {
        let isActive = note.name.rawValue.hasSuffix("dndstart")
        Task { @MainActor in
            self.isFocusActive = isActive
            self.onFocusChanged?(isActive)
        }
    }
}
