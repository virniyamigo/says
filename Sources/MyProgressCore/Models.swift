import Foundation

public enum ActivityCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case learning, programming, english, psychology, sport
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .learning: return "Навчання"
        case .programming: return "Програмування"
        case .english: return "Англійська"
        case .psychology: return "Психологія"
        case .sport: return "Спорт"
        }
    }
    public var symbol: String {
        switch self {
        case .learning: return "graduationcap"
        case .programming: return "chevron.left.forwardslash.chevron.right"
        case .english: return "character.bubble"
        case .psychology: return "heart.text.square"
        case .sport: return "figure.run"
        }
    }
}

public enum TrackingSource: String, Codable, Sendable { case manual, automatic }

public struct ActivitySession: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var category: ActivityCategory
    public var startedAt: Date
    public var endedAt: Date
    public var source: TrackingSource
    public var taskID: UUID?
    public var note: String
    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
    public init(id: UUID = UUID(), category: ActivityCategory, startedAt: Date,
                endedAt: Date, source: TrackingSource = .manual, taskID: UUID? = nil, note: String = "") {
        self.id = id; self.category = category; self.startedAt = startedAt
        self.endedAt = endedAt; self.source = source; self.taskID = taskID; self.note = note
    }
}

public struct ProgressTask: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var category: ActivityCategory
    public var createdAt: Date
    public var dueAt: Date?
    public var completedAt: Date?
    public var isCompleted: Bool { completedAt != nil }
    public init(id: UUID = UUID(), title: String, category: ActivityCategory,
                createdAt: Date = Date(), dueAt: Date? = nil, completedAt: Date? = nil) {
        self.id = id; self.title = title; self.category = category
        self.createdAt = createdAt; self.dueAt = dueAt; self.completedAt = completedAt
    }
}

public struct CategoryGoal: Codable, Equatable, Sendable {
    public var category: ActivityCategory
    public var dailyMinutes: Int
    public init(category: ActivityCategory, dailyMinutes: Int = 30) {
        self.category = category; self.dailyMinutes = dailyMinutes
    }
}

public struct AutomaticRule: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var bundleIdentifier: String
    public var category: ActivityCategory
    public var pauseWhenIdle: Bool
    public init(id: UUID = UUID(), bundleIdentifier: String, category: ActivityCategory, pauseWhenIdle: Bool = true) {
        self.id = id; self.bundleIdentifier = bundleIdentifier; self.category = category; self.pauseWhenIdle = pauseWhenIdle
    }
    private enum CodingKeys: String, CodingKey { case id, bundleIdentifier, category, pauseWhenIdle }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        bundleIdentifier = try values.decode(String.self, forKey: .bundleIdentifier)
        category = try values.decode(ActivityCategory.self, forKey: .category)
        pauseWhenIdle = try values.decodeIfPresent(Bool.self, forKey: .pauseWhenIdle) ?? true
    }
}

public struct TrackingSettings: Codable, Equatable, Sendable {
    public var automaticEnabled = false
    public var idleSeconds: TimeInterval = 120
    public var rules: [AutomaticRule] = [
        .init(bundleIdentifier: "com.apple.dt.Xcode", category: .programming),
        .init(bundleIdentifier: "com.microsoft.VSCode", category: .programming)
    ]
    public init() {}
}

public struct LegacyTotal: Codable, Equatable, Sendable {
    public var category: ActivityCategory
    public var seconds: TimeInterval
    public init(category: ActivityCategory, seconds: TimeInterval) {
        self.category = category; self.seconds = seconds
    }
}

public struct Achievement: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var unlockedAt: Date
    public init(id: String, unlockedAt: Date) { self.id = id; self.unlockedAt = unlockedAt }
}

public struct ProgressDocument: Codable, Equatable, Sendable {
    public var version = 2
    public var sessions: [ActivitySession] = []
    public var activeSessionID: UUID?
    public var tasks: [ProgressTask] = []
    public var goals = ActivityCategory.allCases.map { CategoryGoal(category: $0) }
    public var journal: [JournalEntry] = []
    public var legacyTotals: [LegacyTotal] = []
    public var achievements: [Achievement] = []
    public var settings = TrackingSettings()
    // Additive fields keep version-1 data readable and retain every existing model.
    public var outcomes: [OutcomeRecord] = []
    public var outcomeGoals: [OutcomeGoal] = [
        .init(category: .programming, metric: .commits, target: 5),
        .init(category: .programming, metric: .completedTasks, target: 3),
        .init(category: .english, metric: .lessons, target: 5),
        .init(category: .learning, metric: .lessons, target: 3)
    ]
    public var gitTracking = GitTrackingConfiguration()
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case version, sessions, activeSessionID, tasks, goals, journal, legacyTotals, achievements, settings
        case outcomes, outcomeGoals, gitTracking
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try values.decode(Int.self, forKey: .version)
        version = storedVersion == 1 ? 2 : storedVersion
        sessions = try values.decode([ActivitySession].self, forKey: .sessions)
        activeSessionID = try values.decodeIfPresent(UUID.self, forKey: .activeSessionID)
        tasks = try values.decode([ProgressTask].self, forKey: .tasks)
        goals = try values.decode([CategoryGoal].self, forKey: .goals)
        journal = try values.decode([JournalEntry].self, forKey: .journal)
        legacyTotals = try values.decode([LegacyTotal].self, forKey: .legacyTotals)
        achievements = try values.decode([Achievement].self, forKey: .achievements)
        settings = try values.decode(TrackingSettings.self, forKey: .settings)
        outcomes = try values.decodeIfPresent([OutcomeRecord].self, forKey: .outcomes) ?? []
        if let savedGoals = try values.decodeIfPresent([OutcomeGoal].self, forKey: .outcomeGoals) { outcomeGoals = savedGoals }
        gitTracking = try values.decodeIfPresent(GitTrackingConfiguration.self, forKey: .gitTracking) ?? .init()
    }
}

public enum TimeText {
    public static func short(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "—" }
        let minutes = Int(min(max(0, seconds), Double(Int.max / 2)) / 60)
        return "\(minutes / 60) год \(minutes % 60) хв"
    }
    public static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "—" }
        let value = Int(min(max(0, seconds), Double(Int.max / 2)))
        return String(format: "%02d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60)
    }
}
