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
    public func save(_ document: ProgressDocument) throws {
        try validate(document)
        let data = try JSONEncoder().encode(document)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    public func validate(_ document: ProgressDocument) throws {
        guard document.version == 1 else { throw DocumentError.unsupportedVersion(document.version) }
        func unique<T: Hashable>(_ ids: [T]) -> Bool { Set(ids).count == ids.count }
        guard unique(document.sessions.map(\.id)), unique(document.tasks.map(\.id)),
              unique(document.journal.map(\.id)), unique(document.achievements.map(\.id)),
              unique(document.goals.map(\.category)), unique(document.legacyTotals.map(\.category)),
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
