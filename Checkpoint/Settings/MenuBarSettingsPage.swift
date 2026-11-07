import SwiftUI

/// What stays in view between check-ins.
struct MenuBarSettingsPage: View {
    @AppStorage(AppSettings.Key.menuBarDisplay.rawValue) private var menuBarDisplay = AppSettings.Default.menuBarDisplay
    @AppStorage(AppSettings.Key.showFocusPill.rawValue) private var showFocusPill = AppSettings.Default.showFocusPill

    var body: some View {
        Form {
            Section("Menu Bar") {
                Picker("Show", selection: $menuBarDisplay) {
                    Text("Time on current objective").tag(AppSettings.MenuBarDisplay.objectiveTime)
                    Text("Countdown to next check-in").tag(AppSettings.MenuBarDisplay.countdown)
                }
                SettingNote("Time on your objective keeps time visible. A countdown lets you anticipate check-ins, which makes them less effective.")
            }

            Section("Focus Strip") {
                Toggle("Show my current focus at the top of the screen", isOn: $showFocusPill)
                SettingNote("A small strip with your objective and time on it. Never takes focus, hidden from screen sharing (see Privacy), and hidden while paused or away. Drag to move; double-click to change.")
            }
        }
        .formStyle(.grouped)
    }
}
