import Combine
import SwiftUI

/// App actions that SwiftUI views (Settings) can trigger.
final class AppCommands: ObservableObject {
    let changeObjective: () -> Void
    let showHowItWorks: () -> Void

    init(changeObjective: @escaping () -> Void = {}, showHowItWorks: @escaping () -> Void = {}) {
        self.changeObjective = changeObjective
        self.showHowItWorks = showHowItWorks
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
