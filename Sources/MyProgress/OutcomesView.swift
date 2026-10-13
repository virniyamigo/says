import SwiftUI
import Charts
import MyProgressCore

extension ActivityCategory {
    var resultMetrics: [OutcomeMetric] {
        switch self {
        case .programming: return [.commits, .completedTasks]
        case .english: return [.words, .lessons, .films, .conversations]
        case .learning: return [.lessons, .exercises]
        case .psychology: return [.journalEntries, .completedTasks]
        case .sport: return [.workouts, .completedTasks]
        }
    }
}

struct OutcomeSummary: View {
    let category: ActivityCategory
    @EnvironmentObject private var tracker: ActivityTracker
    @State private var adding = false
    @State private var learningReport = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Результати цього тижня").font(.title2.bold())
                Spacer()
                if category == .english || category == .learning {
                    Button("Звіт ChatGPT…") { learningReport = true }
                }
                if category != .psychology { Button("Додати результат…") { adding = true } }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(category.resultMetrics) { metric in
                    StatCard(title: metric.title,
                             value: "\(tracker.outcomeStats.quantity(metric: metric, category: category, in: Calendar.current.dateInterval(of: .weekOfYear, for: Date())))",
                             symbol: metric.symbol, tint: category.tint)
                }
            }
        }
        .sheet(isPresented: $adding) { OutcomeEditor(defaultCategory: category) }
        .sheet(isPresented: $learningReport) { LearningReportView() }
    }
}

struct OutcomesView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @State private var category: ActivityCategory?
    @State private var metric = OutcomeMetric.commits
    @State private var adding = false
    @State private var addingGoal = false
    @State private var editingGoal: OutcomeGoal?
    @State private var report = false
    @State private var deleting: UUID?
    private var availableMetrics: [OutcomeMetric] {
        guard let category else { return OutcomeMetric.allCases }
        return OutcomeMetric.allCases.filter { $0.supports(category) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "Результати", subtitle: "Не лише проведений час — конкретні завершені кроки", symbol: "target")
                HStack {
                    Button("Додати результат…") { adding = true }.buttonStyle(.borderedProminent)
                    Button("Звіт ChatGPT…") { report = true }
                    Button("Імпорт CSV…") { tracker.importCSV() }
                    Spacer()
                    Button("Нова ціль…") { addingGoal = true }
                }
                if let message = tracker.resultMessage { Text(message).font(.callout).foregroundStyle(.secondary) }
                Text("Цілі").font(.title2.bold())
                ForEach(tracker.document.outcomeGoals.filter { category == nil || $0.category == category }) { goal in
                    HStack {
                        OutcomeGoalCard(goal: goal)
                        Button { editingGoal = goal } label: { Image(systemName: "pencil") }
                        Button(role: .destructive) { tracker.deleteOutcomeGoal(goal.id) } label: { Image(systemName: "trash") }
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Picker("Напрям", selection: $category) {
                                Text("Усі").tag(nil as ActivityCategory?)
                                ForEach(ActivityCategory.allCases) { Text($0.title).tag(Optional($0)) }
                            }
                            Picker("Результат", selection: $metric) {
                                ForEach(availableMetrics) { Text($0.title).tag($0) }
                            }
                        }
                        let days = tracker.outcomeStats.days(metric: metric, category: category)
                        HStack {
                            MetricView(title: "За 7 днів", value: "\(days.reduce(0) { $0 + $1.quantity })")
                            MetricView(title: "За весь час", value: "\(tracker.outcomeStats.quantity(metric: metric, category: category))")
                        }
                        Chart(days) { day in
                            BarMark(x: .value("День", day.date, unit: .day), y: .value(metric.title, day.quantity))
                                .foregroundStyle(category?.tint ?? .cyan).cornerRadius(5)
                        }.frame(height: 200).chartYAxisLabel(metric.title)
                    }
                }
                Text("Останні результати").font(.title2.bold())
                if metric.isDerived {
                    EmptyPanel(title: "Оновлюється автоматично", detail: "Виконані задачі та записи щоденника враховуються з відповідних розділів. Додавати дублікати не потрібно.", symbol: metric.symbol)
                } else {
                    let records = tracker.document.outcomes.filter { $0.metric == metric && (category == nil || $0.category == category) }.sorted { $0.date > $1.date }
                    if records.isEmpty {
                        EmptyPanel(title: "Історія починається з першого кроку", detail: metric == .commits ? "Додай локальний Git-репозиторій у налаштуваннях і ввімкни синхронізацію." : "Додай результат або встав підсумок заняття з ChatGPT.", symbol: metric.symbol)
                    }
                    ForEach(Array(records.prefix(100))) { record in
                        Panel {
                            HStack(spacing: 16) {
                                Image(systemName: record.metric.symbol).foregroundStyle(record.category.tint).font(.title2)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.note.isEmpty ? record.metric.title : record.note).lineLimit(3)
                                    Text("\(record.category.title) · \(record.source.title) · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("+\(record.quantity)").font(.title2.bold()).monospacedDigit()
                                if record.source != .git {
                                    Button(role: .destructive) { deleting = record.id } label: { Image(systemName: "trash") }
                                }
                            }
                        }
                    }
                }
                Text("Коміти фіксують зміну коду, але не оцінюють його якість. Слова й уроки зі звіту ChatGPT — підтверджений вами підсумок заняття, а не автоматична перевірка знань.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(30)
        }
        .sheet(isPresented: $adding) { OutcomeEditor(defaultCategory: category ?? .english) }
        .sheet(isPresented: $addingGoal) { OutcomeGoalEditor(goal: nil, defaultCategory: category ?? .programming) }
        .sheet(item: $editingGoal) { OutcomeGoalEditor(goal: $0, defaultCategory: $0.category) }
        .sheet(isPresented: $report) { LearningReportView() }
        .onChange(of: category) { _, value in
            if let value, !metric.supports(value) { metric = value.resultMetrics[0] }
        }
        .alert("Видалити результат?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Видалити", role: .destructive) { if let id = deleting { tracker.deleteOutcome(id) }; deleting = nil }
            Button("Скасувати", role: .cancel) { deleting = nil }
        }
    }
}

struct OutcomeEditor: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @Environment(\.dismiss) private var dismiss
    @State private var category: ActivityCategory
    @State private var metric: OutcomeMetric
    @State private var quantity = 1
    @State private var date = Date()
    @State private var note = ""
    init(defaultCategory: ActivityCategory) {
        let supportedCategory: ActivityCategory = defaultCategory == .psychology ? .learning : defaultCategory
        _category = State(initialValue: supportedCategory)
        _metric = State(initialValue: OutcomeMetric.allCases.first { !$0.isDerived && $0.supports(supportedCategory) } ?? .lessons)
    }
    var body: some View {
        Form {
            Text("Зафіксувати результат").font(.title2.bold())
            Picker("Напрям", selection: $category) {
                ForEach(ActivityCategory.allCases.filter { $0 != .psychology }) { Text($0.title).tag($0) }
            }
            Picker("Результат", selection: $metric) {
                ForEach(OutcomeMetric.allCases.filter { !$0.isDerived && $0.supports(category) }) { Text($0.title).tag($0) }
            }
            TextField("Кількість", value: $quantity, format: .number)
            DatePicker("Коли", selection: $date, in: ...Date())
            TextField("Що зроблено / назва фільму", text: $note)
            HStack {
                Button("Скасувати") { dismiss() }
                Button("Зберегти") {
                    tracker.addOutcome(category: category, metric: metric, quantity: quantity, date: date, note: note)
                    if tracker.storageError == nil { dismiss() }
                }.buttonStyle(.borderedProminent).disabled(!(1...1_000_000).contains(quantity))
            }
        }.padding(24).frame(width: 500)
        .onChange(of: category) { _, value in
            metric = OutcomeMetric.allCases.first { !$0.isDerived && $0.supports(value) } ?? .lessons
        }
    }
}

struct OutcomeGoalEditor: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @Environment(\.dismiss) private var dismiss
    let goal: OutcomeGoal?
    @State private var category: ActivityCategory
    @State private var metric: OutcomeMetric
    @State private var target: Int
    @State private var period: GoalPeriod
    init(goal: OutcomeGoal?, defaultCategory: ActivityCategory) {
        self.goal = goal
        _category = State(initialValue: goal?.category ?? defaultCategory)
        _metric = State(initialValue: goal?.metric ?? defaultCategory.resultMetrics[0])
        _target = State(initialValue: goal?.target ?? 5)
        _period = State(initialValue: goal?.period ?? .weekly)
    }
    var body: some View {
        Form {
            Text(goal == nil ? "Нова ціль" : "Редагування цілі").font(.title2.bold())
            Picker("Напрям", selection: $category) { ForEach(ActivityCategory.allCases) { Text($0.title).tag($0) } }
            Picker("Результат", selection: $metric) { ForEach(OutcomeMetric.allCases.filter { $0.supports(category) }) { Text($0.title).tag($0) } }
            TextField("Цільова кількість", value: $target, format: .number)
            Picker("Період", selection: $period) { ForEach(GoalPeriod.allCases) { Text($0.title).tag($0) } }
            HStack {
                Button("Скасувати") { dismiss() }
                Button("Зберегти") {
                    let next = OutcomeGoal(id: goal?.id ?? UUID(), category: category, metric: metric, target: target, period: period)
                    if goal == nil { tracker.addOutcomeGoal(next) } else { tracker.updateOutcomeGoal(next) }
                    if tracker.storageError == nil { dismiss() }
                }.buttonStyle(.borderedProminent).disabled(!(1...1_000_000).contains(target))
            }
        }.padding(24).frame(width: 500)
        .onChange(of: category) { _, value in if !metric.supports(value) { metric = value.resultMetrics[0] } }
    }
}
