import Combine
import SwiftUI

/// App actions that SwiftUI views (Settings) can trigger.
final class AppCommands: ObservableObject {
    let changeObjective: () -> Void
    let showHowItWorks: () -> Void
    /// Label/value rows describing what the app is doing right now (Settings › Diagnostics).
    let diagnostics: () -> [(label: String, value: String)]

    init(changeObjective: @escaping () -> Void = {},
         showHowItWorks: @escaping () -> Void = {},
         diagnostics: @escaping () -> [(label: String, value: String)] = { [] }) {
        self.changeObjective = changeObjective
        self.showHowItWorks = showHowItWorks
        self.diagnostics = diagnostics
    }
}

@main
struct CheckpointApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
                .environmentObject(appDelegate.customStore)
                .environmentObject(appDelegate.objectiveTracker)
                .environmentObject(appDelegate.commands)
        }
    }
}
