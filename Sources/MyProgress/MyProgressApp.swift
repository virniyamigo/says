import SwiftUI
import AppKit

@main
@MainActor
struct MyProgressApp: App {
    @AppStorage("myprogress.showMenuBar") private var showMenuBar = true
    @AppStorage("myprogress.appearance") private var appearance = "dark"
    private var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
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
        Window("My Progress", id: "main") {
            ContentView()
                .environmentObject(tracker)
                .environmentObject(journal)
                .frame(minWidth: 1060, minHeight: 720)
                .preferredColorScheme(colorScheme)
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .commands {
            CommandMenu("Трекінг") {
                Button("Зупинити ручну сесію") { tracker.stopManual() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Експортувати резервну копію…") { tracker.exportData() }
            }
        }
        MenuBarExtra("My Progress", systemImage: "chart.line.uptrend.xyaxis", isInserted: $showMenuBar) {
            MenuBarControls().environmentObject(tracker)
        }
        Settings { TrackingSettingsView().environmentObject(tracker).preferredColorScheme(colorScheme) }
    }
}
