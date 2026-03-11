import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            NotificationsSettingsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            QuestionsSettingsView()
                .tabItem {
                    Label("Questions", systemImage: "text.bubble")
                }

            HistorySettingsView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 440, maxHeight: .infinity)
        .background(WindowResizer(size: NSSize(width: 620, height: 560)))
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
