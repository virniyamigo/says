import SwiftUI
import MyProgressCore

struct StatisticsView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @State private var count = 30
    @State private var category: ActivityCategory?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "Статистика", subtitle: "Ритм і баланс за днями та напрямами", symbol: "chart.bar.xaxis")
                HStack {
                    Picker("Період", selection: $count) {
                        Text("7 днів").tag(7); Text("30 днів").tag(30); Text("90 днів").tag(90)
                    }
                    Picker("Напрям", selection: $category) {
                        Text("Усі").tag(nil as ActivityCategory?)
                        ForEach(ActivityCategory.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                }
                let days = tracker.stats.days(count: count, category: category)
                HStack {
                    MetricView(title: "За період", value: TimeText.short(days.reduce(0) { $0 + $1.seconds }))
                    MetricView(title: "Активні дні (від 1 хв)", value: "\(days.filter { $0.seconds >= 60 }.count)")
                    MetricView(title: "За весь час", value: TimeText.short(tracker.stats.total(category: category)))
                }
                Panel { DailyChart(days: days) }
                Text("Розподіл за напрямами").font(.title2.bold())
                ForEach(ActivityCategory.allCases.filter { category == nil || $0 == category }) { item in
                    let seconds = days.reduce(0.0) { result, day in
                        guard let interval = Calendar.current.dateInterval(of: .day, for: day.date) else { return result }
                        return result + tracker.stats.seconds(in: interval, category: item)
                    }
                    ProgressRow(title: item.title, time: seconds)
                }
                Text("Історія за днями").font(.title2.bold())
                ForEach(days.reversed()) { day in
                    HStack { Text(day.date, style: .date); Spacer(); Text(TimeText.short(day.seconds)) }
                }
                Text("Сесії через північ розподіляються між днями. Попередні підсумки без дат показуються лише в загальному часі.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(30)
        }
    }
}

struct AchievementsView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: "Досягнення", subtitle: "Кожен завершений крок має значення", symbol: "trophy")
                Text("Відкриті досягнення зберігаються, навіть якщо ви пізніше зміните історію.").foregroundStyle(.secondary)
                ForEach(AchievementDefinition.all) { definition in
                    let unlocked = tracker.document.achievements.first { $0.id == definition.id }
                    HStack(spacing: 16) {
                        Image(systemName: unlocked == nil ? "lock" : "trophy.fill").font(.title).foregroundStyle(unlocked == nil ? .gray : .orange)
                        VStack(alignment: .leading) {
                            Text(definition.title).font(.headline)
                            Text(definition.detail).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let unlocked { Text(unlocked.unlockedAt, style: .date).font(.caption) }
                    }.padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                }
            }.padding(30)
        }
    }
}
