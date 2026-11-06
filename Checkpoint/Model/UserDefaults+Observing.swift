import Foundation

/// Observable through Combine (`publisher(for:)`). KVO on `UserDefaults` only works when the
/// property name is the stored key, so each name must match its `AppSettings.Key` raw value.
extension UserDefaults {
    @objc dynamic var currentObjective: String? {
        return string(forKey: "currentObjective")
    }

    @objc dynamic var currentIfThenPlan: String? {
        return string(forKey: "currentIfThenPlan")
    }

    @objc dynamic var showFocusPill: Bool {
        return AppSettings(self).showFocusPill
    }

    @objc dynamic var checkpointInterval: Int {
        return integer(forKey: AppSettings.Key.checkInInterval.rawValue)
    }
}
