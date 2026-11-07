import SwiftUI

/// The pages of the Settings sidebar (#82), grouped as in Apple's HIG for sidebars: two levels
/// at most, short labels, SF Symbols in the accent colour.
nonisolated enum SettingsPage: String, CaseIterable, Identifiable {
    case now, checkIns, schedule, interruptions, menuBar, privacy, questions, history, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: return "Now"
        case .checkIns: return "Check-ins"
        case .schedule: return "Schedule"
        case .interruptions: return "Interruptions"
        case .menuBar: return "Menu Bar"
        case .privacy: return "Privacy"
        case .questions: return "Questions"
        case .history: return "History"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .now: return "target"
        case .checkIns: return "clock.badge.checkmark"
        case .schedule: return "calendar"
        case .interruptions: return "bell"
        case .menuBar: return "menubar.rectangle"
        case .privacy: return "hand.raised"
        case .questions: return "text.bubble"
        case .history: return "clock.arrow.circlepath"
        case .about: return "info.circle"
        }
    }

    /// Sidebar groups, in order. Nil header: the top item stands alone.
    static let groups: [(header: String?, pages: [SettingsPage])] = [
        (nil, [.now]),
        ("Check-ins", [.checkIns, .schedule, .interruptions]),
        ("Display", [.menuBar, .privacy]),
        ("Your Data", [.questions, .history]),
        ("App", [.about]),
    ]
}

/// The short "what this does and why" line under a setting, in one style everywhere.
struct SettingNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
