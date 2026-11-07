import SwiftUI

/// Who else can see your objective and goals.
struct PrivacySettingsPage: View {
    @AppStorage(AppSettings.Key.hideFromScreenCapture.rawValue) private var hideFromScreenCapture = AppSettings.Default.hideFromScreenCapture

    var body: some View {
        Form {
            Section("Screen Sharing and Screenshots") {
                Toggle("Hide check-ins from screen sharing and screenshots", isOn: $hideFromScreenCapture)
                SettingNote(hideFromScreenCapture
                    ? "On: the check-in card and focus strip never appear in screen shares, recordings or screenshots, so your objective and goals stay private on calls."
                    : "Off: they appear in screen shares, recordings and screenshots. The card says so in its corner while this is off.")
            }
            Section("Your Data") {
                SettingNote("Everything stays on this Mac, in ~/Library/Application Support/Checkpoint. Nothing is sent anywhere.")
            }
        }
        .formStyle(.grouped)
    }
}
