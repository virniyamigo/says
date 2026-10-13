import Foundation
import Combine
import AppKit
import CoreGraphics
import MyProgressCore

/// App-wide replacement for the original per-view timer; survives navigation changes.
@MainActor
final class ActivityTracker: ObservableObject {
    @Published private(set) var document = ProgressDocument()
    @Published private(set) var storageError: String?
    @Published private(set) var manualCategory: ActivityCategory?
    @Published private(set) var status = "Трекінг зупинено"
    @Published private(set) var frontmostBundleID = ""
    private var manualTaskID: UUID?
    private var recorder = SessionRecorder()
    private var timer: Timer?
    private var sleeping = false
    private var observers: [NSObjectProtocol] = []
    private var terminationObserver: NSObjectProtocol?
    private var storageUnavailable = false
    let repository: DocumentRepository

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        repository = DocumentRepository(url: base.appendingPathComponent("MyProgress/progress-v1.json"))
        do {
            document = try repository.load() ?? DocumentRepository.migrate(defaults: .standard)
            // A restored session ends at its last persisted observation, never at the next launch.
            document.activeSessionID = nil
            document.sessions.removeAll { $0.duration == 0 }
            try repository.save(document)
        } catch {
            storageUnavailable = true
            storageError = "Не вдалося відкрити дані: \(error.localizedDescription)\n\(repository.url.path)"
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = false }
        })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = false }
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = false }
        })
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopAll() }
        }
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    var stats: ProgressStatistics { .init(document: document) }
    var activeSession: ActivitySession? { document.sessions.first { $0.id == document.activeSessionID } }
    var writable: Bool { !storageUnavailable }

    private func commit(_ change: (inout ProgressDocument) -> Void) {
        guard writable else { return }
        var next = document
        change(&next)
        AchievementDefinition.update(&next)
        do {
            try repository.save(next)
            document = next
            storageError = nil
        } catch {
            storageError = "Збереження не вдалося: \(error.localizedDescription). Трекінг зупинено; дані в пам’яті збережено."
            storageUnavailable = true
            manualCategory = nil
            status = "Помилка збереження"
        }
    }
    func retryStorage() {
        guard storageUnavailable else { return }
        // Never overwrite an unreadable initial file with an empty in-memory document.
        do {
            if let loaded = try repository.load() {
                document = loaded
                document.activeSessionID = nil
            } else {
                document = try DocumentRepository.migrate(defaults: .standard)
            }
            try repository.save(document)
            storageUnavailable = false; storageError = nil
            recorder = SessionRecorder()
        } catch { storageError = error.localizedDescription }
    }
    func start(_ category: ActivityCategory, taskID: UUID? = nil) {
        guard writable else { return }
        manualCategory = category; manualTaskID = taskID
        sample()
    }
    func stopManual() {
        manualCategory = nil; manualTaskID = nil
        finishSession()
        sample()
    }
    func stopAll() {
        manualCategory = nil; manualTaskID = nil
        finishSession()
    }
    private func finishSession() {
        var nextRecorder = recorder
        commit { nextRecorder.stop(document: &$0, now: Date()) }
        recorder = nextRecorder
    }
    private func suspend() {
        sleeping = true
        finishSession()
        status = "Пауза: сон або вимкнений екран"
    }
    private func sample() {
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        guard writable else { return }
        // Query ages of actual input types; .null is not an "any user input" event.
        // No event tap is installed and no keystrokes or pointer coordinates are read.
        let inputTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .mouseMoved,
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged,
            .rightMouseDragged, .otherMouseDragged, .scrollWheel, .tabletPointer]
        let idle = inputTypes.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.filter { $0.isFinite && $0 >= 0 }.min() ?? .infinity
        var category: ActivityCategory?
        var source: TrackingSource = .manual
        if sleeping || idle >= document.settings.idleSeconds {
            status = "Пауза: бездіяльність або сон"
        } else if let manualCategory {
            category = manualCategory
            status = "Вручну: \(manualCategory.title)"
        } else if document.settings.automaticEnabled,
                  let rule = document.settings.rules.first(where: { $0.bundleIdentifier == frontmostBundleID }) {
            category = rule.category; source = .automatic
            status = "Автоматично: \(rule.category.title)"
        } else {
            status = document.settings.automaticEnabled ? "Очікування програми з правилом" : "Трекінг зупинено"
        }
        if category == nil && document.activeSessionID == nil { return }
        var nextRecorder = recorder
        commit { nextRecorder.observe(document: &$0, category: category, source: source,
                                      taskID: source == .manual ? manualTaskID : nil, now: Date()) }
        recorder = nextRecorder
    }
    func addTask(title: String, category: ActivityCategory, dueAt: Date?) {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        commit { $0.tasks.insert(.init(title: text, category: category, dueAt: dueAt), at: 0) }
    }
    func updateTask(_ task: ProgressTask) {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        commit { next in
            guard let index = next.tasks.firstIndex(where: { $0.id == task.id }) else { return }
            next.tasks[index] = task; next.tasks[index].title = title
        }
    }
    func toggleTask(_ id: UUID) {
        if manualTaskID == id { stopManual() }
        commit { next in
            guard let i = next.tasks.firstIndex(where: { $0.id == id }) else { return }
            next.tasks[i].completedAt = next.tasks[i].isCompleted ? nil : Date()
        }
    }
    func deleteTask(_ id: UUID) {
        if manualTaskID == id { stopManual() }
        commit { $0.tasks.removeAll { $0.id == id } }
    }
    func setGoal(_ category: ActivityCategory, minutes: Int) {
        commit { next in
            if let i = next.goals.firstIndex(where: { $0.category == category }) { next.goals[i].dailyMinutes = minutes }
        }
    }
    func setAutomatic(_ enabled: Bool) {
        commit { $0.settings.automaticEnabled = enabled }
        sample()
    }
    func setIdle(_ seconds: TimeInterval) { commit { $0.settings.idleSeconds = seconds } }
    func addRule(bundleID: String, category: ActivityCategory) {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        commit { next in
            if let i = next.settings.rules.firstIndex(where: { $0.bundleIdentifier == id }) {
                next.settings.rules[i].category = category
            } else { next.settings.rules.append(.init(bundleIdentifier: id, category: category)) }
        }
    }
    func removeRule(_ id: UUID) { commit { $0.settings.rules.removeAll { $0.id == id } }; sample() }
    func addSession(category: ActivityCategory, date: Date, minutes: Int, note: String) {
        guard minutes > 0, minutes <= 1440, date.addingTimeInterval(Double(minutes) * 60) <= Date() else { return }
        commit { $0.sessions.append(.init(category: category, startedAt: date,
                                        endedAt: date.addingTimeInterval(Double(minutes) * 60), note: note)) }
    }
    func deleteSession(_ id: UUID) {
        guard id != document.activeSessionID else { return }
        commit { $0.sessions.removeAll { $0.id == id } }
    }
    func addNote(category: String, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        commit { $0.journal.insert(.init(category: category, text: text), at: 0) }
    }
    func deleteNote(_ id: UUID) { commit { $0.journal.removeAll { $0.id == id } } }
    func importData() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let candidate = try JSONDecoder().decode(ProgressDocument.self, from: Data(contentsOf: url))
            try repository.validate(candidate)
            let alert = NSAlert()
            alert.messageText = "Замінити поточні дані резервною копією?"
            alert.informativeText = "Сесій: \(candidate.sessions.count), задач: \(candidate.tasks.count), записів: \(candidate.journal.count). Поточні дані буде збережено в окремій резервній копії."
            alert.addButton(withTitle: "Відновити"); alert.addButton(withTitle: "Скасувати")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            stopAll()
            let backup = repository.url.deletingLastPathComponent().appendingPathComponent("backup-\(UUID().uuidString).json")
            if FileManager.default.fileExists(atPath: repository.url.path) {
                // Preserve original bytes, including an unreadable file, before explicit recovery.
                try FileManager.default.copyItem(at: repository.url, to: backup)
            } else {
                try DocumentRepository(url: backup).save(document)
            }
            var restored = candidate
            restored.activeSessionID = nil
            try repository.save(restored)
            document = restored; recorder = SessionRecorder(); storageError = nil
            storageUnavailable = false; manualCategory = nil; manualTaskID = nil
            status = "Дані відновлено"
        } catch { storageError = "Відновлення не вдалося: \(error.localizedDescription)" }
    }
    func exportData() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MyProgress-backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: url, options: .atomic)
        } catch { storageError = "Експорт не вдався: \(error.localizedDescription)" }
    }
}
