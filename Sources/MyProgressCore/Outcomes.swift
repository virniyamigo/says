import Foundation

public enum OutcomeMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case commits, completedTasks, lessons, exercises, words, films, conversations, workouts, journalEntries
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .commits: return "Коміти"
        case .completedTasks: return "Виконані задачі"
        case .lessons: return "Завершені уроки"
        case .exercises: return "Виконані вправи"
        case .words: return "Опрацьовані слова"
        case .films: return "Переглянуті фільми"
        case .conversations: return "Практика розмови"
        case .workouts: return "Тренування"
        case .journalEntries: return "Записи щоденника"
        }
    }
    public var symbol: String {
        switch self {
        case .commits: return "arrow.triangle.branch"
        case .completedTasks: return "checkmark.circle"
        case .lessons: return "book.closed"
        case .exercises: return "pencil.and.list.clipboard"
        case .words: return "character.bubble"
        case .films: return "film"
        case .conversations: return "bubble.left.and.bubble.right"
        case .workouts: return "figure.run"
        case .journalEntries: return "heart.text.square"
        }
    }
    public var isDerived: Bool { self == .completedTasks || self == .journalEntries }
    public func supports(_ category: ActivityCategory) -> Bool {
        switch self {
        case .commits: return category == .programming
        case .completedTasks: return true
        case .lessons, .exercises: return [.learning, .english, .programming].contains(category)
        case .words: return category == .english
        case .films, .conversations: return [.english, .learning].contains(category)
        case .workouts: return category == .sport
        case .journalEntries: return category == .psychology
        }
    }
}

public enum OutcomeSource: String, Codable, Sendable {
    case manual, git, imported
    public var title: String {
        switch self {
        case .manual: return "Вручну"
        case .git: return "Git"
        case .imported: return "Імпорт"
        }
    }
}

public struct OutcomeRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var category: ActivityCategory
    public var metric: OutcomeMetric
    public var quantity: Int
    public var date: Date
    public var source: OutcomeSource
    public var reference: String?
    public var note: String
    public init(id: UUID = UUID(), category: ActivityCategory, metric: OutcomeMetric,
                quantity: Int, date: Date = Date(), source: OutcomeSource = .manual,
                reference: String? = nil, note: String = "") {
        self.id = id; self.category = category; self.metric = metric; self.quantity = quantity
        self.date = date; self.source = source; self.reference = reference; self.note = note
    }
}

public enum GoalPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily, weekly
    public var id: String { rawValue }
    public var title: String { self == .daily ? "На день" : "На тиждень" }
    public func interval(now: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: self == .daily ? .day : .weekOfYear, for: now)
    }
}

public struct OutcomeGoal: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var category: ActivityCategory
    public var metric: OutcomeMetric
    public var target: Int
    public var period: GoalPeriod
    public init(id: UUID = UUID(), category: ActivityCategory, metric: OutcomeMetric, target: Int, period: GoalPeriod = .weekly) {
        self.id = id; self.category = category; self.metric = metric; self.target = target; self.period = period
    }
}

public struct TrackedGitRepository: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var path: String
    public var authorEmail: String
    public init(id: UUID = UUID(), path: String, authorEmail: String = "") {
        self.id = id; self.path = path; self.authorEmail = authorEmail
    }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public struct GitTrackingConfiguration: Codable, Equatable, Sendable {
    public var enabled = false
    public var completeReferencedTasks = false
    public var repositories: [TrackedGitRepository] = []
    public init() {}
}

public struct DailyOutcome: Identifiable, Equatable, Sendable {
    public var date: Date
    public var quantity: Int
    public var id: Date { date }
}

public struct OutcomeStatistics {
    public let document: ProgressDocument
    public var calendar: Calendar
    public init(document: ProgressDocument, calendar: Calendar = .current) {
        self.document = document; self.calendar = calendar
    }
    public func quantity(metric: OutcomeMetric, category: ActivityCategory? = nil, in interval: DateInterval? = nil) -> Int {
        func includes(_ date: Date) -> Bool {
            guard let interval else { return true }
            return date >= interval.start && date < interval.end
        }
        switch metric {
        case .completedTasks:
            return document.tasks.filter {
                (category == nil || $0.category == category) && $0.completedAt.map(includes) == true
            }.count
        case .journalEntries:
            guard category == nil || category == .psychology else { return 0 }
            return document.journal.filter {
                $0.category == "Psychology" && !$0.text.hasPrefix("AI-рефлексія") && includes($0.createdAt)
            }.count
        default:
            return document.outcomes.filter {
                $0.metric == metric && (category == nil || $0.category == category) && includes($0.date)
            }.reduce(0) { $0 + $1.quantity }
        }
    }
    public func progress(_ goal: OutcomeGoal, now: Date = Date()) -> Int {
        guard let interval = goal.period.interval(now: now, calendar: calendar) else { return 0 }
        return quantity(metric: goal.metric, category: goal.category, in: interval)
    }
    public func days(count: Int = 7, metric: OutcomeMetric, category: ActivityCategory? = nil, now: Date = Date()) -> [DailyOutcome] {
        guard count > 0 else { return [] }
        let start = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: start),
                  let interval = calendar.dateInterval(of: .day, for: day) else { return nil }
            return DailyOutcome(date: day, quantity: quantity(metric: metric, category: category, in: interval))
        }
    }
}

public enum OutcomeAutomation {
    /// Imported references are immutable event identities; the same event never accumulates twice.
    @discardableResult
    public static func merge(_ records: [OutcomeRecord], into document: inout ProgressDocument) -> Int {
        var references = Set(document.outcomes.compactMap(\.reference))
        var ids = Set(document.outcomes.map(\.id))
        var count = 0
        for record in records {
            guard !ids.contains(record.id) else { continue }
            if let reference = record.reference, !references.insert(reference).inserted { continue }
            document.outcomes.append(record); ids.insert(record.id); count += 1
        }
        return count
    }
    public static func taskCode(_ id: UUID) -> String { "MP-" + id.uuidString.prefix(8) }
    public static func referencedTask(in message: String, tasks: [ProgressTask]) -> UUID? {
        let pattern = #"(?i)\b(?:done|fixes|closes|resolves|готово)\s+(MP-[0-9a-f]{8})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = message as NSString
        let matches = regex.matches(in: message, range: NSRange(location: 0, length: ns.length))
        // Only one unambiguous task per commit is auto-completed.
        let codes = Set(matches.map { ns.substring(with: $0.range(at: 1)).uppercased() })
        let matching = tasks.filter { $0.category == .programming && codes.contains(taskCode($0.id)) }
        return matching.count == 1 ? matching.first?.id : nil
    }
    public static func mergeCommits(_ commits: [GitCommit], into document: inout ProgressDocument, now: Date = Date()) -> Int {
        var count = 0
        var references = Set(document.outcomes.compactMap(\.reference))
        for commit in commits.sorted(by: { $0.date < $1.date }) where commit.date <= now {
            let result = OutcomeRecord(category: .programming, metric: .commits, quantity: 1,
                                       date: commit.date, source: .git, reference: "git:\(commit.hash)",
                                       note: commit.subject)
            guard let reference = result.reference, references.insert(reference).inserted else { continue }
            document.outcomes.append(result)
            count += 1
            if document.gitTracking.completeReferencedTasks,
               let id = referencedTask(in: commit.subject, tasks: document.tasks),
               let index = document.tasks.firstIndex(where: { $0.id == id }),
               !document.tasks[index].isCompleted, commit.date >= document.tasks[index].createdAt {
                document.tasks[index].completedAt = commit.date
            }
        }
        return count
    }
}
