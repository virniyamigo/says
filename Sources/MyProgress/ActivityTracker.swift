import Foundation
import Combine
import AppKit
import CoreGraphics
import MyProgressCore
import UniformTypeIdentifiers

/// App-wide replacement for the original per-view timer; survives navigation changes.
@MainActor
final class ActivityTracker: ObservableObject {
    @Published private(set) var document = ProgressDocument()
    @Published private(set) var storageError: String?
    @Published private(set) var manualCategory: ActivityCategory?
    @Published private(set) var status = "Трекінг зупинено"
    @Published private(set) var frontmostBundleID = ""
    @Published private(set) var gitStatus = "Оберіть локальні репозиторії в налаштуваннях"
    @Published private(set) var gitRefreshing = false
    @Published private(set) var lastGitSync: Date?
    @Published private(set) var resultMessage: String?
    private var lastGitAttempt = Date.distantPast
    private var manualPassive = false
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
            try repository.backupVersionOneIfNeeded()
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

    var outcomeStats: OutcomeStatistics { .init(document: document) }
    var stats: ProgressStatistics { .init(document: document) }
    var activeSession: ActivitySession? { document.sessions.first { $0.id == document.activeSessionID } }
    var writable: Bool { !storageUnavailable }

    private func commit(_ change: (inout ProgressDocument) -> Void) {
        guard writable else { return }
        var next = document
        change(&next)
        AchievementDefinition.update(&next)
        guard next != document else { return }
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
                try repository.backupVersionOneIfNeeded()
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
    func start(_ category: ActivityCategory, taskID: UUID? = nil, passive: Bool = false) {
        guard writable else { return }
        manualCategory = category; manualTaskID = taskID; manualPassive = passive
        sample()
    }
    func stopManual() {
        manualCategory = nil; manualTaskID = nil; manualPassive = false
        finishSession()
        sample()
    }
    func stopAll() {
        manualCategory = nil; manualTaskID = nil; manualPassive = false
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
        if document.gitTracking.enabled && Date().timeIntervalSince(lastGitAttempt) >= 60 { refreshGit() }
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
        let rule = document.settings.rules.first { $0.bundleIdentifier == frontmostBundleID }
        let shouldPauseForIdle = manualCategory != nil ? !manualPassive : (rule?.pauseWhenIdle ?? true)
        if sleeping || (shouldPauseForIdle && idle >= document.settings.idleSeconds) {
            status = "Пауза: бездіяльність або сон"
        } else if let manualCategory {
            category = manualCategory
            status = "Вручну: \(manualCategory.title)"
        } else if document.settings.automaticEnabled,
                  let rule {
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
    func addRule(bundleID: String, category: ActivityCategory, pauseWhenIdle: Bool = true) {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        commit { next in
            if let i = next.settings.rules.firstIndex(where: { $0.bundleIdentifier == id }) {
                next.settings.rules[i].category = category
                next.settings.rules[i].pauseWhenIdle = pauseWhenIdle
            } else { next.settings.rules.append(.init(bundleIdentifier: id, category: category, pauseWhenIdle: pauseWhenIdle)) }
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
    func chooseAutomaticApp(category: ActivityCategory, passive: Bool) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        addRule(bundleID: id, category: category, pauseWhenIdle: !passive)
        setAutomatic(true)
    }
    func setRuleIdle(_ id: UUID, enabled: Bool) {
        commit { next in
            if let index = next.settings.rules.firstIndex(where: { $0.id == id }) { next.settings.rules[index].pauseWhenIdle = enabled }
        }
    }
    func addOutcome(category: ActivityCategory, metric: OutcomeMetric, quantity: Int, date: Date, note: String) {
        guard date <= Date(), metric.supports(category), !metric.isDerived, (1...1_000_000).contains(quantity) else { return }
        commit { $0.outcomes.append(.init(category: category, metric: metric, quantity: quantity, date: date, note: note)) }
    }
    func deleteOutcome(_ id: UUID) {
        // Git facts remain immutable so a polling scan cannot re-import a deleted fact.
        commit { $0.outcomes.removeAll { $0.id == id && $0.source != .git } }
    }
    func addOutcomeGoal(_ goal: OutcomeGoal) { commit { $0.outcomeGoals.append(goal) } }
    func deleteOutcomeGoal(_ id: UUID) { commit { $0.outcomeGoals.removeAll { $0.id == id } } }
    func updateOutcomeGoal(_ goal: OutcomeGoal) {
        commit { next in
            if let index = next.outcomeGoals.firstIndex(where: { $0.id == goal.id }) { next.outcomeGoals[index] = goal }
        }
    }
    func importOutcomes(_ records: [OutcomeRecord]) {
        var count = 0
        commit { count = OutcomeAutomation.merge(records, into: &$0) }
        if storageError == nil { resultMessage = "Додано результатів: \(count). Повторні записи пропущено." }
    }
    func importCSV() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { importOutcomes(try OutcomeCSV.read(String(contentsOf: url, encoding: .utf8))) }
        catch { resultMessage = error.localizedDescription }
    }
    func setGitEnabled(_ enabled: Bool) {
        commit { $0.gitTracking.enabled = enabled }
        if enabled { refreshGit() }
    }
    func setGitTaskCompletion(_ enabled: Bool) { commit { $0.gitTracking.completeReferencedTasks = enabled } }
    func chooseGitRepository() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let repo = try await Task.detached { try GitReader.inspect(path: url.path) }.value
                commit { next in
                    if !next.gitTracking.repositories.contains(where: { $0.path == repo.path }) { next.gitTracking.repositories.append(repo) }
                }
                if document.gitTracking.enabled { refreshGit() }
            } catch { gitStatus = error.localizedDescription }
        }
    }
    func updateGitAuthor(_ id: UUID, email: String) {
        commit { next in
            if let index = next.gitTracking.repositories.firstIndex(where: { $0.id == id }) {
                next.gitTracking.repositories[index].authorEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if document.gitTracking.enabled { refreshGit() }
    }
    func removeGitRepository(_ id: UUID) { commit { $0.gitTracking.repositories.removeAll { $0.id == id } } }
    func refreshGit() {
        guard writable, document.gitTracking.enabled, !gitRefreshing else { return }
        let repositories = document.gitTracking.repositories
        guard !repositories.isEmpty else { gitStatus = "Оберіть локальну папку Git-репозиторію"; lastGitAttempt = Date(); return }
        gitRefreshing = true; lastGitAttempt = Date()
        Task {
            let since = Date().addingTimeInterval(-30 * 86400)
            let results = await Task.detached {
                repositories.map { repo -> (UUID, Result<[GitCommit], Error>) in
                    (repo.id, Result { try GitReader.commits(repository: repo, since: since) })
                }
            }.value
            defer { gitRefreshing = false }
            guard document.gitTracking.enabled else { return }
            var commits: [GitCommit] = []; var errors: [String] = []
            for (id, result) in results {
                guard let original = repositories.first(where: { $0.id == id }),
                      document.gitTracking.repositories.contains(original) else { continue }
                switch result {
                case .success(let values): commits.append(contentsOf: values)
                case .failure(let error): errors.append(error.localizedDescription)
                }
            }
            var count = 0
            commit { count = OutcomeAutomation.mergeCommits(commits, into: &$0) }
            guard writable else { return }
            lastGitSync = Date()
            gitStatus = errors.isEmpty ? "Оновлено: +\(count) нових комітів" : "Часткове оновлення: +\(count). " + errors.joined(separator: " ")
        }
    }
    func importData() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let candidate = try JSONDecoder().decode(ProgressDocument.self, from: Data(contentsOf: url))
            try repository.validate(candidate)
            let alert = NSAlert()
            alert.messageText = "Замінити поточні дані резервною копією?"
            alert.informativeText = "Результатів: \(candidate.outcomes.count). Сесій: \(candidate.sessions.count), задач: \(candidate.tasks.count), записів: \(candidate.journal.count). Поточні дані буде збережено в окремій резервній копії."
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
