import AppKit
import ServiceManagement
import SwiftUI

/// Version, Start at Login, how the app works, and Diagnostics.
struct AboutSettingsPage: View {
    @EnvironmentObject private var commands: AppCommands
    @State private var launchAtLogin = false
    @State private var showDiagnostics = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(AppInfo.displayString)
                        .textSelection(.enabled)
                    Spacer()
                    Button("How Checkpoint Works…") { commands.showHowItWorks() }
                }
            }

            Section("Startup") {
                Toggle("Start at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue  // revert on failure
                        }
                    }
                SettingNote("Check-ins only happen while Checkpoint is running, so it's best to start it when you log in.")
            }

            Section {
                // Tucked away on purpose: knowing when the next check-in comes lets you brace for it
                DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        let rows = commands.diagnostics()
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(rows, id: \.label) { row in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(row.label)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 120, alignment: .leading)
                                    Text(row.value)
                                        .textSelection(.enabled)
                                }
                                .font(.system(size: 11).monospacedDigit())
                            }
                            HStack {
                                Text("For checking that things work. Knowing when check-ins come makes them less effective, so this stays collapsed.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Button("Copy") {
                                    let text = rows.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(text, forType: .string)
                                }
                                .controlSize(.small)
                            }
                            .padding(.top, 4)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Reads the login state; opening Settings never changes a setting
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
