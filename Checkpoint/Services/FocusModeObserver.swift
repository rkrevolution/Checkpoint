import Foundation

@MainActor
final class FocusModeObserver: NSObject {

    var onFocusChanged: ((Bool) -> Void)?
    private(set) var isFocusActive: Bool = false

    func startObserving() {
        // Sync current Focus mode state at launch by checking assertion status
        syncCurrentState()

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

    private func syncCurrentState() {
        // Read the DND preferences plist to check if Focus is currently active
        let prefsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        if let data = try? Data(contentsOf: prefsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let store = json["data"] as? [[String: Any]] {
            let active = !store.isEmpty
            isFocusActive = active
            onFocusChanged?(active)
        }
    }

    @objc nonisolated private func dndDidChange(_ note: Notification) {
        let isActive = note.name.rawValue.hasSuffix("dndstart")
        Task { @MainActor in
            self.isFocusActive = isActive
            self.onFocusChanged?(isActive)
        }
    }
}
