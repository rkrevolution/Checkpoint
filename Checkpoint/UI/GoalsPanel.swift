import SwiftUI

/// One goal line: the scope mark and the full text. Goals wrap rather than truncate,
/// because a cut-off goal can't do its job of holding the bigger picture for you.
struct GoalRow: View {
    let goal: String
    var fontSize: CGFloat = 13

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: fontSize - 2, weight: .semibold))
                .foregroundStyle(.secondary)  // grey: the orange target belongs to the objective
            Text(goal)
                .font(.system(size: fontSize, weight: .medium))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// The goals, grouped in a quiet inset box: one per line, each in full. Shown at the moments you
/// decide what to do next (the check-in card and the objective prompt), so the goals don't have to
/// be held in working memory. Calmer than the objective above it: the objective is what you're on,
/// the goals are why. A single goal goes without the header, which would outweigh it.
/// Renders nothing when no goals are set.
struct GoalsPanel: View {
    let goals: [String]

    var body: some View {
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if goals.count > 1 {
                    Text("Your goals")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(0.6)
                }
                ForEach(Array(goals.enumerated()), id: \.offset) { _, goal in
                    GoalRow(goal: goal)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel((goals.count > 1 ? "Your goals: " : "Your goal: ") + goals.joined(separator: ", "))
        }
    }
}

#Preview {
    GoalsPanel(goals: ["Ship Checkpoint 1.0", "Run 3× a week", "Read one book a month, a long goal that wraps onto a second line"])
        .padding()
        .frame(width: 440)
}
