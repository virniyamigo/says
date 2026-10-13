import SwiftUI
import AppKit
import ServiceManagement
import MyProgressCore

struct MenuBarControls: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(tracker.status)
        Text("Сьогодні: \(TimeText.short(tracker.stats.today()))")
        Divider()
        Button("Відкрити My Progress") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button("Сесія програмування") { tracker.start(.programming) }
        Button("Практика англійської") { tracker.start(.english) }
        Button("Перегляд фільму англійською") { tracker.start(.english, passive: true) }
        if tracker.manualCategory != nil { Button("Завершити ручну сесію") { tracker.stopManual() } }
        Button("Зупинити облік часу") { tracker.setAutomatic(false); tracker.stopManual() }
        Divider()
        Button("Вийти з My Progress") { NSApplication.shared.terminate(nil) }
    }
}

struct LoginSettingsView: View {
    @State private var enabled = false
    @State private var message = ""
    @State private var changing = false
    private var bundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Запускати My Progress при вході в macOS", isOn: Binding(get: { enabled }, set: { setEnabled($0) }))
                .disabled(!bundled || changing)
            Text(bundled ? "Застосунок має залишатися відкритим, щоб відстежувати час і локальні Git-коміти." : "Автозапуск доступний у .app-збірці. Зберіть її скриптом build-macos-app.sh та перемістіть у Applications.")
                .font(.caption).foregroundStyle(.secondary)
            if !message.isEmpty { Text(message).font(.caption) }
            if SMAppService.mainApp.status == .requiresApproval {
                Button("Відкрити налаштування входу macOS") { SMAppService.openSystemSettingsLoginItems() }
            }
        }.onAppear { enabled = SMAppService.mainApp.status == .enabled }
    }
    private func setEnabled(_ value: Bool) {
        changing = true
        Task { @MainActor in
            defer { changing = false }
            do {
                if value { try SMAppService.mainApp.register() } else { try await SMAppService.mainApp.unregister() }
                enabled = SMAppService.mainApp.status == .enabled
                message = SMAppService.mainApp.status == .requiresApproval ? "Підтвердіть дозвіл у налаштуваннях входу macOS." : "Налаштування збережено."
            } catch { message = error.localizedDescription; enabled = SMAppService.mainApp.status == .enabled }
        }
    }
}
