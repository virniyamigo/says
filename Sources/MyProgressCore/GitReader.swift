import Foundation

public struct GitCommit: Equatable, Sendable {
    public var hash: String
    public var date: Date
    public var subject: String
    public init(hash: String, date: Date, subject: String) { self.hash = hash; self.date = date; self.subject = subject }
}

public enum GitReadError: LocalizedError {
    case failed, missingAuthor, tooManyCommits, malformed
    public var errorDescription: String? {
        switch self {
        case .failed: return "Не вдалося прочитати Git. Перевірте папку репозиторію та встановлення Xcode Command Line Tools."
        case .missingAuthor: return "У репозиторії немає user.email. Вкажіть email автора в налаштуваннях Git-трекінгу."
        case .tooManyCommits: return "За 30 днів знайдено понад 10 000 комітів. Цей репозиторій не імпортовано."
        case .malformed: return "Git повернув некоректний формат записів."
        }
    }
}

/// Read-only local Git integration. It never fetches, pushes, or executes a shell.
public enum GitReader {
    private static func run(path: String, arguments: [String], allowFailure: Bool = false) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "log.showSignature=false", "-C", path] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard allowFailure || process.terminationStatus == 0 else { throw GitReadError.failed }
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
    public static func inspect(path: String) throws -> TrackedGitRepository {
        let (_, root) = try run(path: path, arguments: ["rev-parse", "--show-toplevel"])
        let clean = root.trimmingCharacters(in: .whitespacesAndNewlines)
        let (_, email) = try run(path: clean, arguments: ["config", "user.email"], allowFailure: true)
        return .init(path: URL(fileURLWithPath: clean).resolvingSymlinksInPath().path,
                     authorEmail: email.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    public static func commits(repository: TrackedGitRepository, since: Date) throws -> [GitCommit] {
        _ = try run(path: repository.path, arguments: ["rev-parse", "--show-toplevel"])
        let author = repository.authorEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !author.isEmpty else { throw GitReadError.missingAuthor }
        let (refStatus, _) = try run(path: repository.path, arguments: ["show-ref"], allowFailure: true)
        if refStatus == 1 { return [] } // Valid, newly initialized repository without any refs.
        guard refStatus == 0 else { throw GitReadError.failed }
        let (_, raw) = try run(path: repository.path, arguments: ["log", "--all", "--no-merges", "--max-count=10001",
            "--since=@\(Int(since.timeIntervalSince1970))", "--format=%H%x1f%ct%x1f%aE%x1f%s%x1e"])
        return try parse(raw, authorEmail: author, since: since)
    }
    public static func parse(_ output: String, authorEmail: String, since: Date) throws -> [GitCommit] {
        let rows = output.components(separatedBy: "\u{1e}").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard rows.count <= 10000 else { throw GitReadError.tooManyCommits }
        return try rows.compactMap { row in
            let parts = row.trimmingCharacters(in: .newlines).components(separatedBy: "\u{1f}")
            guard parts.count == 4, [40, 64].contains(parts[0].count), parts[0].allSatisfy(\.isHexDigit),
                  let timestamp = TimeInterval(parts[1]), timestamp.isFinite else { throw GitReadError.malformed }
            let date = Date(timeIntervalSince1970: timestamp)
            guard parts[2].caseInsensitiveCompare(authorEmail) == .orderedSame, date >= since else { return nil }
            return GitCommit(hash: parts[0].lowercased(), date: date, subject: parts[3])
        }
    }
}
