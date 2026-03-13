import SwiftUI

struct WelcomeView: View {
    var onGetStarted: (Int) -> Void  // passes selected interval in seconds

    @State private var selectedInterval = 2700  // 45 min default

    private let intervalOptions: [(label: String, seconds: Int)] = [
        ("15 min", 900),
        ("30 min", 1800),
        ("45 min", 2700),
        ("60 min", 3600),
        ("90 min", 5400),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App identity
            VStack(spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Checkpoint")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text("A gentle tap on the shoulder at regular intervals.\nSee the time, read a question, get back to work.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Spacer()
                .frame(height: 28)

            // Quick setup
            VStack(alignment: .leading, spacing: 16) {
                Text("Quick Setup")
                    .font(.headline)

                // Interval picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("How often should I check in?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Interval", selection: $selectedInterval) {
                        ForEach(intervalOptions, id: \.seconds) { option in
                            Text(option.label).tag(option.seconds)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Timing varies slightly each time to stay noticeable.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(20)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            Spacer()
                .frame(height: 20)

            // How it works
            VStack(alignment: .leading, spacing: 8) {
                Label("A prompt appears showing the current time and a grounding question", systemImage: "clock")
                Label("Tap \"Got it\" to acknowledge and return to work", systemImage: "checkmark.circle")
                Label("Tap \"Not now\" to snooze for a few minutes", systemImage: "clock.arrow.circlepath")
                Label("Look for the sun icon in your menu bar for a countdown to the next check-in", systemImage: "sun.max.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            // Action
            HStack {
                Text("You can always change these in Preferences (\u{2318},)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    UserDefaults.standard.set(selectedInterval, forKey: "checkpointInterval")
                    onGetStarted(selectedInterval)
                } label: {
                    Text("Start Checkpoints")
                        .font(.body.weight(.medium))
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
        .padding(32)
        .frame(width: 480, height: 520)
    }
}

#Preview {
    WelcomeView(onGetStarted: { _ in })
}
