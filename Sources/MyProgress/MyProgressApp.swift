import SwiftUI
import AppKit

@main
@MainActor
struct MyProgressApp: App {
    @StateObject private var tracker: ActivityTracker
    @StateObject private var journal: JournalStore
    init() {
        // Swift Package executables may begin without a regular app activation policy.
        // Set it before WindowGroup creates windows rather than waiting for onAppear.
        NSApplication.shared.setActivationPolicy(.regular)
        let tracker = ActivityTracker()
        _tracker = StateObject(wrappedValue: tracker)
        _journal = StateObject(wrappedValue: JournalStore(tracker: tracker))
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tracker)
                .environmentObject(journal)
                .frame(minWidth: 960, minHeight: 650)
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .commands {
            CommandMenu("Трекінг") {
                Button("Зупинити ручну сесію") { tracker.stopManual() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Експортувати резервну копію…") { tracker.exportData() }
            }
        }
        Settings { TrackingSettingsView().environmentObject(tracker) }
    }
}
