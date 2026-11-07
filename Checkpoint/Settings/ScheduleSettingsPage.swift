import SwiftUI

/// When check-ins may happen: active hours and days.
struct ScheduleSettingsPage: View {
    @AppStorage(AppSettings.Key.useActiveHours.rawValue) private var useActiveHours = AppSettings.Default.useActiveHours
    @AppStorage(AppSettings.Key.activeHoursStart.rawValue) private var activeHoursStart = AppSettings.Default.activeHoursStart
    @AppStorage(AppSettings.Key.activeHoursEnd.rawValue) private var activeHoursEnd = AppSettings.Default.activeHoursEnd
    @State private var skipWeekdays: [Int] = AppSettings().skipWeekdays

    var body: some View {
        Form {
            Section("Active Hours") {
                Toggle("Limit to active hours", isOn: $useActiveHours)
                if useActiveHours {
                    HStack {
                        Picker("Start", selection: $activeHoursStart) {
                            ForEach(0..<24, id: \.self) { hour in Text(Self.hourLabel(hour)).tag(hour) }
                        }
                        .frame(width: 160)
                        Text("to")
                            .foregroundStyle(.secondary)
                        Picker("End", selection: $activeHoursEnd) {
                            ForEach(0..<24, id: \.self) { hour in Text(Self.hourLabel(hour)).tag(hour) }
                        }
                        .frame(width: 160)
                    }
                    SettingNote("Check-ins only come during these hours. When they end, Today opens with a summary of your day.")
                } else {
                    SettingNote("Off: check-ins come whenever Checkpoint is running and you're at your Mac.")
                }
            }

            Section("Days") {
                // Days shown in the user's calendar order (#29)
                HStack(spacing: 4) {
                    Text("Check in on")
                    Spacer()
                    ForEach(Weekdays.ordered(), id: \.self) { weekday in
                        Toggle(Weekdays.shortName(weekday), isOn: Binding(
                            get: { !skipWeekdays.contains(weekday) },
                            set: { on in
                                skipWeekdays = Weekdays.setSkipped(weekday, skipped: !on, in: skipWeekdays)
                                AppSettings().skipWeekdays = skipWeekdays
                            }
                        ))
                        .toggleStyle(.button)
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: 0)) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
