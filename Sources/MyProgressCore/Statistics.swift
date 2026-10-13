import Foundation

public struct DayTotal: Identifiable, Equatable, Sendable {
    public var date: Date
    public var seconds: TimeInterval
    public var id: Date { date }
}

public struct ProgressStatistics {
    public let document: ProgressDocument
    public var calendar: Calendar
    public init(document: ProgressDocument, calendar: Calendar = .current) {
        self.document = document; self.calendar = calendar
    }
    public func total(category: ActivityCategory? = nil) -> TimeInterval {
        document.sessions.filter { category == nil || $0.category == category }.reduce(0) { $0 + $1.duration }
        + document.legacyTotals.filter { category == nil || $0.category == category }.reduce(0) { $0 + $1.seconds }
    }
    public func seconds(in interval: DateInterval, category: ActivityCategory? = nil) -> TimeInterval {
        document.sessions.filter { category == nil || $0.category == category }.reduce(0) { value, session in
            value + max(0, min(session.endedAt, interval.end).timeIntervalSince(max(session.startedAt, interval.start)))
        }
    }
    public func today(category: ActivityCategory? = nil, now: Date = Date()) -> TimeInterval {
        guard let interval = calendar.dateInterval(of: .day, for: now) else { return 0 }
        return seconds(in: interval, category: category)
    }
    public func days(count: Int = 7, ending now: Date = Date(), category: ActivityCategory? = nil) -> [DayTotal] {
        guard count > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today),
                  let interval = calendar.dateInterval(of: .day, for: date) else { return nil }
            return DayTotal(date: date, seconds: seconds(in: interval, category: category))
        }
    }
    // An active day has at least one minute; an unfinished current day does not break yesterday's streak.
    public func streak(now: Date = Date()) -> Int {
        var count = 0
        var day = calendar.startOfDay(for: now)
        for index in 0..<3660 {
            guard let interval = calendar.dateInterval(of: .day, for: day) else { break }
            let active = seconds(in: interval) >= 60
            if index != 0 || active {
                guard active else { break }
                count += 1
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
    public func taskSeconds(_ id: UUID) -> TimeInterval {
        document.sessions.filter { $0.taskID == id }.reduce(0) { $0 + $1.duration }
    }
}

public struct AchievementDefinition: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public static let all: [Self] = [
        .init(id: "first-session", title: "Перший крок", detail: "Одна хвилина активності"),
        .init(id: "ten-hours", title: "10 годин розвитку", detail: "10 годин сумарної активності"),
        .init(id: "first-task", title: "Зроблено", detail: "Перша виконана задача"),
        .init(id: "ten-tasks", title: "Результативність", detail: "10 виконаних задач"),
        .init(id: "three-days", title: "Ритм", detail: "3 активні дні поспіль"),
        .init(id: "first-note", title: "Саморефлексія", detail: "Перший запис у щоденнику"),
        .init(id: "first-git", title: "Код у дії", detail: "Перший автоматично врахований Git-коміт"),
        .init(id: "result-goal", title: "Мету досягнуто", detail: "Виконана ціль за результатами")
    ]
    public static func update(_ document: inout ProgressDocument, now: Date = Date(), calendar: Calendar = .current) {
        let stats = ProgressStatistics(document: document, calendar: calendar)
        let completed = document.tasks.filter(\.isCompleted).count
        var ids: [String] = []
        if document.sessions.reduce(0.0, { $0 + $1.duration }) >= 60 { ids.append("first-session") }
        if stats.total() >= 36000 { ids.append("ten-hours") }
        if completed >= 1 { ids.append("first-task") }
        if completed >= 10 { ids.append("ten-tasks") }
        if !document.achievements.contains(where: { $0.id == "three-days" }), stats.streak(now: now) >= 3 {
            ids.append("three-days")
        }
        if !document.journal.isEmpty { ids.append("first-note") }
        if document.outcomes.contains(where: { $0.source == .git }) { ids.append("first-git") }
        let outcomes = OutcomeStatistics(document: document, calendar: calendar)
        if document.outcomeGoals.contains(where: { outcomes.progress($0, now: now) >= $0.target }) { ids.append("result-goal") }
        for id in ids where !document.achievements.contains(where: { $0.id == id }) {
            document.achievements.append(.init(id: id, unlockedAt: now))
        }
    }
}
