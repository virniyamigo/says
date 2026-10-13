import SwiftUI
import MyProgressCore

struct TasksView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @State private var category: ActivityCategory?
    @State private var showCompleted = false
    @State private var editing: ProgressTask?
    @State private var adding = false
    @State private var deleting: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                PageHeading(title: "Задачі", subtitle: "Конкретні кроки, які перетворюють час на результат", symbol: "checklist")
                Spacer()
                Button("Нова задача…") { adding = true }.buttonStyle(.borderedProminent)
            }
            HStack {
                Picker("Напрям", selection: $category) {
                    Text("Усі").tag(nil as ActivityCategory?)
                    ForEach(ActivityCategory.allCases) { Text($0.title).tag(Optional($0)) }
                }.frame(width: 270)
                Toggle("Показати виконані", isOn: $showCompleted)
            }
            let tasks = tracker.document.tasks.filter {
                (category == nil || $0.category == category) && (showCompleted || !$0.isCompleted)
            }.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            if tasks.isEmpty { Text("Немає задач для цього фільтра.").foregroundStyle(.secondary) }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(tasks) { task in
                        HStack {
                            TaskRow(task: task)
                            Button { editing = task } label: { Image(systemName: "pencil") }.help("Редагувати")
                            Button(role: .destructive) { deleting = task.id } label: { Image(systemName: "trash") }
                        }.padding().background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }.padding(30)
        .sheet(isPresented: $adding) { TaskEditor(task: nil, defaultCategory: category ?? .learning) }
        .sheet(item: $editing) { TaskEditor(task: $0, defaultCategory: $0.category) }
        .alert("Видалити задачу?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Видалити", role: .destructive) { if let id = deleting { tracker.deleteTask(id) }; deleting = nil }
            Button("Скасувати", role: .cancel) { deleting = nil }
        } message: { Text("Записані сесії залишаться в історії.") }
    }
}

struct TaskRow: View {
    let task: ProgressTask
    @EnvironmentObject private var tracker: ActivityTracker
    var body: some View {
        HStack {
            Button { tracker.toggleTask(task.id) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
            }.buttonStyle(.plain).help(task.isCompleted ? "Повернути до активних" : "Виконати")
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title).strikethrough(task.isCompleted)
                HStack {
                    Text(task.category.title)
                    if task.category == .programming {
                        Text(OutcomeAutomation.taskCode(task.id)).monospaced().textSelection(.enabled)
                    }
                    if let due = task.dueAt {
                        Text(due, style: .date).foregroundStyle(!task.isCompleted && due < Calendar.current.startOfDay(for: Date()) ? .red : .secondary)
                    }
                    Text(TimeText.short(tracker.stats.taskSeconds(task.id)))
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !task.isCompleted {
                Button { tracker.start(task.category, taskID: task.id) } label: { Image(systemName: "play.fill") }
                    .help("Почати сесію для задачі")
            }
        }
    }
}

struct TaskEditor: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @Environment(\.dismiss) private var dismiss
    let task: ProgressTask?
    @State private var title: String
    @State private var category: ActivityCategory
    @State private var hasDue: Bool
    @State private var due: Date
    init(task: ProgressTask?, defaultCategory: ActivityCategory) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _category = State(initialValue: task?.category ?? defaultCategory)
        _hasDue = State(initialValue: task?.dueAt != nil)
        _due = State(initialValue: task?.dueAt ?? Date())
    }
    var body: some View {
        Form {
            Text(task == nil ? "Нова задача" : "Редагування задачі").font(.title2.bold())
            TextField("Назва", text: $title)
            Picker("Напрям", selection: $category) { ForEach(ActivityCategory.allCases) { Text($0.title).tag($0) } }
            Toggle("Термін виконання", isOn: $hasDue)
            if hasDue { DatePicker("Дата", selection: $due, displayedComponents: .date) }
            HStack {
                Button("Скасувати") { dismiss() }
                Button("Зберегти") {
                    if var task {
                        task.title = title; task.category = category; task.dueAt = hasDue ? due : nil
                        tracker.updateTask(task)
                    } else { tracker.addTask(title: title, category: category, dueAt: hasDue ? due : nil) }
                    if tracker.storageError == nil { dismiss() }
                }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 500)
    }
}
