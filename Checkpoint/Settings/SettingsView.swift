import AppKit
import SwiftUI

/// Settings: a sidebar of pages (#82), following Apple's HIG for sidebars. Opens on the page
/// viewed last.
struct SettingsView: View {
    @AppStorage(AppSettings.Key.settingsPage.rawValue) private var page = AppSettings.Default.settingsPage

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<SettingsPage?>(
                get: { page },
                set: { if let new = $0 { page = new } }
            )) {
                ForEach(SettingsPage.groups, id: \.pages.first?.id) { group in
                    Section {
                        ForEach(group.pages) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    } header: {
                        if let header = group.header { Text(header) }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detail(for: page)
                .navigationTitle(page.title)
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 440, maxHeight: .infinity)
        .background(WindowResizer(size: NSSize(width: 760, height: 560)))
    }

    @ViewBuilder
    private func detail(for page: SettingsPage) -> some View {
        switch page {
        case .now: NowSettingsPage()
        case .checkIns: CheckInsSettingsPage()
        case .schedule: ScheduleSettingsPage()
        case .interruptions: InterruptionsSettingsPage()
        case .menuBar: MenuBarSettingsPage()
        case .privacy: PrivacySettingsPage()
        case .questions: QuestionsSettingsView()
        case .history: HistorySettingsView()
        case .about: AboutSettingsPage()
        }
    }
}

/// Finds its own NSWindow and makes it resizable.
private struct WindowResizer: NSViewRepresentable {
    let size: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.resizable)
            window.setContentSize(size)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
