import SwiftUI
import MyProgressCore

struct ActivityView: View {
    let category: ActivityCategory
    @EnvironmentObject private var tracker: ActivityTracker
    @State private var addingSession = false
    @State private var deletingSession: UUID?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label(category.title, systemImage: category.symbol).font(.largeTitle.bold())
                ActivityControls(category: category)
                HStack {
                    MetricView(title: "Сьогодні", value: TimeText.short(tracker.stats.today(category: category)))
                    MetricView(title: "Загалом", value: TimeText.short(tracker.stats.total(category: category)))
                }
                DailyChart(days: tracker.stats.days(category: category))
                HStack {
                    Text("Історія сесій").font(.title2.bold())
                    Spacer()
                    Button("Додати вручну…") { addingSession = true }
                }
                let sessions = tracker.document.sessions.filter { $0.category == category }.sorted { $0.startedAt > $1.startedAt }
                if sessions.isEmpty { Text("Почніть таймер або внесіть завершену активність вручну.").foregroundStyle(.secondary) }
                ForEach(Array(sessions.prefix(100))) { session in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            Text(session.source == .automatic ? "Автоматично" : "Вручну").font(.caption).foregroundStyle(.secondary)
                            if !session.note.isEmpty { Text(session.note).font(.caption) }
                            if let taskID = session.taskID, let task = tracker.document.tasks.first(where: { $0.id == taskID }) {
                                Text(task.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(TimeText.clock(session.duration)).monospacedDigit()
                        if session.id == tracker.document.activeSessionID {
                            Text("Активна").foregroundStyle(.green)
                        } else {
                            Button(role: .destructive) { deletingSession = session.id } label: { Image(systemName: "trash") }
                        }
                    }.padding().background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if sessions.count > 100 { Text("Показано останні 100 сесій. Повна історія зберігається в резервній копії.").font(.caption) }
            }.padding(30)
        }
        .sheet(isPresented: $addingSession) { ManualSessionView(category: category) }
        .alert("Видалити сесію з історії?", isPresented: Binding(get: { deletingSession != nil }, set: { if !$0 { deletingSession = nil } })) {
            Button("Видалити", role: .destructive) { if let id = deletingSession { tracker.deleteSession(id) }; deletingSession = nil }
            Button("Скасувати", role: .cancel) { deletingSession = nil }
        } message: { Text("Час цієї сесії буде вилучено зі статистики.") }
    }
}

struct ActivityControls: View {
    let category: ActivityCategory
    @EnvironmentObject private var tracker: ActivityTracker
    @State private var selectedTask: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let elapsed = tracker.activeSession.flatMap { $0.category == category ? $0.duration : nil } ?? 0
            Text(TimeText.clock(elapsed))
                .font(.system(size: 48, weight: .bold, design: .monospaced))
            Text(tracker.status).foregroundStyle(.secondary)
            Picker("Задача сесії", selection: $selectedTask) {
                Text("Без задачі").tag(nil as UUID?)
                ForEach(tracker.document.tasks.filter { $0.category == category && !$0.isCompleted }) { task in
                    Text(task.title).tag(Optional(task.id))
                }
            }.frame(maxWidth: 420)
                .disabled(tracker.manualCategory == category)
            HStack {
                Button(tracker.manualCategory == category ? "Зупинити" : "Почати сесію") {
                    if tracker.manualCategory == category { tracker.stopManual() }
                    else { tracker.start(category, taskID: selectedTask) }
                }.buttonStyle(.borderedProminent)
                if tracker.manualCategory == category && tracker.activeSession == nil {
                    Text("Таймер відновиться після активності.").font(.caption)
                }
            }
        }
        .onChange(of: category) { _, _ in selectedTask = nil }
        .onChange(of: tracker.document.tasks) { _, tasks in
            if !tasks.contains(where: { $0.id == selectedTask && !$0.isCompleted }) { selectedTask = nil }
        }
    }
}

struct ManualSessionView: View {
    let category: ActivityCategory
    @EnvironmentObject private var tracker: ActivityTracker
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date().addingTimeInterval(-1800)
    @State private var minutes = 30
    @State private var note = ""
    private var valid: Bool { date.addingTimeInterval(Double(minutes) * 60) <= Date() }
    var body: some View {
        Form {
            Text("Завершена активність: \(category.title)").font(.headline)
            DatePicker("Початок", selection: $date, in: ...Date())
            Stepper("Тривалість: \(minutes) хв", value: $minutes, in: 1...1440)
            TextField("Нотатка", text: $note)
            if !valid { Text("Сесія має завершитися в минулому.").foregroundStyle(.red) }
            HStack {
                Button("Скасувати") { dismiss() }
                Button("Зберегти") {
                    tracker.addSession(category: category, date: date, minutes: minutes, note: note)
                    if tracker.storageError == nil { dismiss() }
                }.disabled(!valid).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 500)
    }
}
