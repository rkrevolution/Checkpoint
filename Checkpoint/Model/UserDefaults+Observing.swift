import Foundation

/// Observable through Combine (`publisher(for:)`). KVO on `UserDefaults` only works when the
/// property name is the stored key, so each name must match its `AppSettings.Key` raw value.
extension UserDefaults {
    @objc dynamic var showFocusPill: Bool {
        return AppSettings(self).showFocusPill
    }

    @objc dynamic var checkpointInterval: Int {
        return integer(forKey: AppSettings.Key.checkInInterval.rawValue)
    }
}
