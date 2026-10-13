import Foundation

public enum DocumentError: LocalizedError {
    case unsupportedVersion(Int), invalidData
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "Непідтримувана версія даних: \(version). Файл залишено без змін."
        case .invalidData: return "Файл даних містить некоректні записи. Його залишено без змін."
        }
    }
}

public struct DocumentRepository {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> ProgressDocument? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let document = try JSONDecoder().decode(ProgressDocument.self, from: Data(contentsOf: url))
        try validate(document)
        return document
    }
    /// Called once before an app writes the new schema, preserving the original bytes.
    @discardableResult
    public func backupVersionOneIfNeeded() throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let bytes = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        guard object?["version"] as? Int == 1 else { return nil }
        let backup = url.deletingLastPathComponent().appendingPathComponent("backup-before-results-\(UUID().uuidString).json")
        try bytes.write(to: backup, options: .atomic)
        return backup
    }
    public func save(_ document: ProgressDocument) throws {
        try validate(document)
        let data = try JSONEncoder().encode(document)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    public func validate(_ document: ProgressDocument) throws {
        guard document.version == 2 else { throw DocumentError.unsupportedVersion(document.version) }
        func unique<T: Hashable>(_ ids: [T]) -> Bool { Set(ids).count == ids.count }
        guard unique(document.sessions.map(\.id)), unique(document.tasks.map(\.id)),
              unique(document.journal.map(\.id)), unique(document.achievements.map(\.id)),
              unique(document.goals.map(\.category)), unique(document.legacyTotals.map(\.category)),
              unique(document.outcomes.map(\.id)), unique(document.outcomes.compactMap(\.reference)),
              unique(document.outcomeGoals.map(\.id)), unique(document.gitTracking.repositories.map(\.id)),
              unique(document.gitTracking.repositories.map(\.path)),
              document.outcomes.allSatisfy({
                  (1...1_000_000).contains($0.quantity) && !$0.metric.isDerived && $0.metric.supports($0.category)
                  && ($0.source == .manual || $0.reference?.isEmpty == false)
                  && ($0.source != .git || ($0.metric == .commits && $0.quantity == 1 && $0.reference?.hasPrefix("git:") == true))
              }),
              document.outcomeGoals.allSatisfy({ (1...1_000_000).contains($0.target) && $0.metric.supports($0.category) }),
              document.gitTracking.repositories.allSatisfy({ $0.path.hasPrefix("/") }),
              unique(document.settings.rules.map(\.id)),
              unique(document.settings.rules.map(\.bundleIdentifier)),
              document.sessions.allSatisfy({ $0.endedAt >= $0.startedAt && $0.duration.isFinite }),
              document.legacyTotals.allSatisfy({ $0.seconds.isFinite && $0.seconds >= 0 }),
              Set(document.goals.map(\.category)) == Set(ActivityCategory.allCases),
              document.tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              document.goals.allSatisfy({ (1...1440).contains($0.dailyMinutes) }),
              (30...3600).contains(document.settings.idleSeconds),
              document.settings.rules.allSatisfy({ !$0.bundleIdentifier.trimmingCharacters(in: .whitespaces).isEmpty }),
              document.activeSessionID == nil || document.sessions.contains(where: { $0.id == document.activeSessionID })
        else { throw DocumentError.invalidData }
    }
    public static func migrate(defaults: UserDefaults) throws -> ProgressDocument {
        var result = ProgressDocument()
        for category in ActivityCategory.allCases {
            let seconds = defaults.double(forKey: "\(category.rawValue).totalTime")
            if seconds > 0 && seconds.isFinite { result.legacyTotals.append(.init(category: category, seconds: seconds)) }
        }
        if let data = defaults.data(forKey: "myprogress.journal.entries.v1") {
            result.journal = try JSONDecoder().decode([JournalEntry].self, from: data)
        }
        AchievementDefinition.update(&result)
        return result
    }
}
