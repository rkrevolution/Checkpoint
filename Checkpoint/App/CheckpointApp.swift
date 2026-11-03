import SwiftUI

extension EnvironmentValues {
    /// Opens the "What are you working on?" prompt (used by Settings).
    @Entry var changeObjective: () -> Void = {}
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
                .environment(\.changeObjective, { appDelegate.updateObjectiveFromMenu() })
        }
    }
}
