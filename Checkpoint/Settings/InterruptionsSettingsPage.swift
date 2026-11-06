import AppKit
import SwiftUI

/// How a check-in gets your attention, and when it waits.
struct InterruptionsSettingsPage: View {
    @AppStorage(AppSettings.Key.playSound.rawValue) private var playSound = AppSettings.Default.playSound
    @AppStorage(AppSettings.Key.soundName.rawValue) private var soundName = AppSettings.Default.soundName
    @AppStorage(AppSettings.Key.fullScreenCheckIn.rawValue) private var fullScreenCheckIn = AppSettings.Default.fullScreenCheckIn
    @AppStorage(AppSettings.Key.showBreathingCue.rawValue) private var showBreathingCue = AppSettings.Default.showBreathingCue
    @AppStorage(AppSettings.Key.snoozeMinutes.rawValue) private var snoozeMinutes = AppSettings.Default.snoozeMinutes
    @AppStorage(AppSettings.Key.maxSnoozes.rawValue) private var maxSnoozes = AppSettings.Default.maxSnoozes
    @AppStorage(AppSettings.Key.afterMaxSnooze.rawValue) private var afterMaxSnooze = AppSettings.Default.afterMaxSnooze
    @AppStorage(AppSettings.Key.holdDuringCalls.rawValue) private var holdDuringCalls = AppSettings.Default.holdDuringCalls
    @AppStorage(AppSettings.Key.respectFocus.rawValue) private var respectFocus = AppSettings.Default.respectFocus

    private let systemSounds = ["Glass", "Ping", "Pop", "Purr", "Sosumi", "Tink"]

    var body: some View {
        Form {
            Section("Getting Your Attention") {
                Toggle("Play sound on check-in", isOn: $playSound)
                if playSound {
                    HStack {
                        Picker("Sound", selection: $soundName) {
                            ForEach(systemSounds, id: \.self) { name in Text(name).tag(name) }
                        }
                        .frame(width: 200)
                        Button("Preview") {
                            NSSound(named: NSSound.Name(soundName))?.play()
                        }
                    }
                }
                Toggle("Full-screen overlay on check-in", isOn: $fullScreenCheckIn)
                SettingNote("Dims and blurs everything behind the check-in to break hyperfocus.")
                Toggle("Show breathing circle on check-in", isOn: $showBreathingCue)
                SettingNote("A gentle pulsing circle to help you pause and take a breath.")
            }

            Section("Not Now") {
                Picker("Snooze for", selection: $snoozeMinutes) {
                    Text("1 min").tag(1)
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("15 min").tag(15)
                }
                Picker("Snoozes per check-in", selection: $maxSnoozes) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("Unlimited").tag(0)
                }
                if maxSnoozes > 0 {
                    Picker("After the last snooze", selection: $afterMaxSnooze) {
                        Text("Drop the check-in").tag(AppSettings.AfterMaxSnooze.autoDismiss)
                        Text("Show it once more, without Not now").tag(AppSettings.AfterMaxSnooze.forceModal)
                    }
                }
                SettingNote("The next check-in always comes a full interval after this one ends.")
            }

            Section("Calls") {
                Toggle("Wait until calls end", isOn: $holdDuringCalls)
                SettingNote(holdDuringCalls
                    ? "On: while any app is using your microphone or camera, a check-in that comes due waits, then appears without sound after the call. Check-ins are not paused or skipped."
                    : "Off: check-ins appear during calls too.")
            }

            Section("Focus") {
                Toggle("Respect macOS Focus / Do Not Disturb", isOn: $respectFocus)
                SettingNote("On: no check-ins while a Focus mode is on. Many people turn Focus on for deep work, which is also when check-ins help most.")
            }
        }
        .formStyle(.grouped)
    }
}
