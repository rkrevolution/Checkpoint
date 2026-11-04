import AppKit
import SwiftUI

struct NotificationsSettingsView: View {
    @AppStorage("playSoundOnCheckpoint") private var playSound = true
    @AppStorage("soundName") private var soundName = "Glass"
    @AppStorage("snoozeMinutes") private var snoozeMinutes = 5
    @AppStorage("maxSnoozesPerCheckpoint") private var maxSnoozes = 2
    @AppStorage("afterMaxSnoozeAction") private var afterMaxSnooze = "autoDismiss"
    @AppStorage("respectFocusMode") private var respectFocusMode = true
    @AppStorage("holdDuringCalls") private var holdDuringCalls = true
    @AppStorage(ScreenCapturePrivacy.key) private var hideFromScreenCapture = ScreenCapturePrivacy.defaultValue

    @AppStorage("showBreathingCue") private var showBreathingCue = false
    @AppStorage("fullScreenCheckpoint") private var fullScreenCheckpoint = false

    private let systemSounds = ["Glass", "Ping", "Pop", "Purr", "Sosumi", "Tink"]

    var body: some View {
        Form {
            Section("Sound") {
                Toggle("Play sound on check-in", isOn: $playSound)

                if playSound {
                    HStack {
                        Picker("Sound", selection: $soundName) {
                            ForEach(systemSounds, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .frame(width: 200)

                        Button("Preview") {
                            NSSound(named: NSSound.Name(soundName))?.play()
                        }
                    }
                }
            }

            Section("Snooze") {
                Picker("Snooze duration", selection: $snoozeMinutes) {
                    Text("1 min").tag(1)
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("15 min").tag(15)
                }

                Picker("Max snoozes per check-in", selection: $maxSnoozes) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("Unlimited").tag(0)
                }

                if maxSnoozes > 0 {
                    Picker("After max snoozes", selection: $afterMaxSnooze) {
                        Text("Auto-dismiss").tag("autoDismiss")
                        Text("Force open modal").tag("forceModal")
                    }
                }
            }

            Section("Attention") {
                Toggle("Full-screen overlay on check-in", isOn: $fullScreenCheckpoint)
                Text("Dims and blurs everything behind the checkpoint to break hyperfocus.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Show breathing circle on check-in", isOn: $showBreathingCue)
                Text("A gentle pulsing circle to help you pause and take a breath.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Calls") {
                Toggle("Wait until calls end", isOn: $holdDuringCalls)
                Text(holdDuringCalls
                     ? "On: while any app is using your microphone or camera, a check-in that comes due waits, then appears without sound after the call. Check-ins are not paused or skipped."
                     : "Off: check-ins appear during calls too.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Screen Sharing and Screenshots") {
                Toggle("Hide check-ins from screen sharing and screenshots", isOn: $hideFromScreenCapture)
                Text(hideFromScreenCapture
                     ? "On: the check-in card and focus strip never appear in screen shares, recordings or screenshots, so your objective and goals stay private on calls."
                     : "Off: they appear in screen shares, recordings and screenshots. The card says so in its corner while this is off.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Focus") {
                Toggle("Respect macOS Focus / Do Not Disturb", isOn: $respectFocusMode)
                Text("Pauses checkpoints during any active Focus mode.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
