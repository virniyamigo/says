import SwiftUI
import Charts
import MyProgressCore

private enum Destination: Hashable {
    case dashboard, activity(ActivityCategory), tasks, statistics, achievements, settings
}

struct ContentView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @State private var selection: Destination? = .dashboard
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Огляд", systemImage: "square.grid.2x2").tag(Destination.dashboard)
                Section("Напрями") {
                    ForEach(ActivityCategory.allCases) { category in
                        Label(category.title, systemImage: category.symbol).tag(Destination.activity(category))
                    }
                }
                Section("Результати") {
                    Label("Задачі", systemImage: "checklist").tag(Destination.tasks)
                    Label("Статистика", systemImage: "chart.bar").tag(Destination.statistics)
                    Label("Досягнення", systemImage: "trophy").tag(Destination.achievements)
                    Label("Налаштування", systemImage: "gear").tag(Destination.settings)
                }
            }
            .navigationTitle("My Progress")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tracker.status).font(.caption)
                    if tracker.manualCategory != nil {
                        Button("Зупинити ручну сесію") { tracker.stopManual() }
                    }
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            VStack(spacing: 0) {
                if let error = tracker.storageError {
                    VStack(alignment: .leading) {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                        HStack {
                            Button("Повторити відкриття") { tracker.retryStorage() }
                            Button("Відновити з копії…") { tracker.importData() }
                            Button("Експортувати доступні дані…") { tracker.exportData() }
                        }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                }
                Group {
                    switch selection ?? .dashboard {
                    case .dashboard: DashboardView()
                    case .activity(let category):
                        if category == .psychology {
                            PsychologyView()
                        } else { ActivityView(category: category) }
                    case .tasks: TasksView()
                    case .statistics: StatisticsView()
                    case .achievements: AchievementsView()
                    case .settings: TrackingSettingsView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .disabled(!tracker.writable)
            }
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Мій прогрес").font(.largeTitle.bold())
                HStack(spacing: 30) {
                    MetricView(title: "Сьогодні", value: TimeText.short(tracker.stats.today()))
                    MetricView(title: "За весь час", value: TimeText.short(tracker.stats.total()))
                    MetricView(title: "Серія днів", value: "\(tracker.stats.streak())")
                    MetricView(title: "Виконані задачі", value: "\(tracker.document.tasks.filter(\.isCompleted).count)")
                }
                Text("Щоденні цілі").font(.title2.bold())
                ForEach(ActivityCategory.allCases) { category in
                    let today = tracker.stats.today(category: category)
                    let goal = tracker.document.goals.first { $0.category == category }?.dailyMinutes ?? 30
                    VStack(alignment: .leading) {
                        ProgressRow(title: category.title, time: today)
                        ProgressView(value: min(today / (Double(goal) * 60), 1))
                        Text("Ціль: \(goal) хв на день").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Останні 7 днів").font(.title2.bold())
                DailyChart(days: tracker.stats.days())
                Text("Найближчі задачі").font(.title2.bold())
                let pending = tracker.document.tasks.filter { !$0.isCompleted }.sorted {
                    ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture)
                }
                if pending.isEmpty { Text("Усе зроблено. Додайте наступну задачу у розділі «Задачі».").foregroundStyle(.secondary) }
                ForEach(Array(pending.prefix(5))) { task in TaskRow(task: task) }
                if !tracker.document.legacyTotals.isEmpty {
                    Text("Попередні підсумки включено в загальний час. Без дат вони не входять до статистики за днями.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(30)
        }
    }
}

struct MetricView: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProgressRow: View {
    let title: String
    let time: TimeInterval
    var body: some View {
        HStack { Text(title).font(.headline); Spacer(); Text(TimeText.short(time)).foregroundStyle(.secondary) }
            .padding().background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DailyChart: View {
    let days: [DayTotal]
    var body: some View {
        Chart(days) { day in
            BarMark(x: .value("День", day.date, unit: .day), y: .value("Хвилини", day.seconds / 60))
                .foregroundStyle(.blue)
        }.chartYAxisLabel("Хвилини").frame(height: 190)
            .accessibilityLabel("Час активності за днями у хвилинах")
    }
}
