import SwiftUI
import AppKit

@main
@MainActor
struct MyProgressApp: App {
    @StateObject private var tracker: ActivityTracker
    @StateObject private var journal: JournalStore
    init() {
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
                .onAppear { NSApplication.shared.setActivationPolicy(.regular) }
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
