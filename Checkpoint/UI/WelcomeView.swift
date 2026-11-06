import SwiftUI

struct WelcomeView: View {
    var onGetStarted: (Int) -> Void  // passes selected interval in seconds

    @State private var selectedInterval = AppSettings.Default.checkInInterval

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

                Text("A tap on the shoulder at unpredictable moments.\nSee the time, answer one question, get back to work.")
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
                ForEach(HowItWorks.steps) { step in
                    Label(step.title, systemImage: step.symbol)
                }
                Text("More any time from the menu bar: How Checkpoint Works…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            // Action
            HStack {
                Text("You can always change these in Settings (\u{2318},)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    AppSettings().checkInInterval = TimeInterval(selectedInterval)
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
