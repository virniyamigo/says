import XCTest
@testable import MyProgressCore

final class OutcomeTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; value.firstWeekday = 2
        return value
    }
    private func day(_ number: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: number, hour: 12))!
    }
    func testOldDocumentAndRulesUpgradeWithoutLosingData() throws {
        var original = ProgressDocument()
        original.tasks = [.init(title: "Keep me", category: .programming)]
        original.journal = [.init(category: "Psychology", text: "Keep this note")]
        original.sessions = [.init(category: .english, startedAt: day(10), endedAt: day(10).addingTimeInterval(60))]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object["version"] = 1
        object.removeValue(forKey: "outcomes"); object.removeValue(forKey: "outcomeGoals"); object.removeValue(forKey: "gitTracking")
        var settings = try XCTUnwrap(object["settings"] as? [String: Any])
        var rules = try XCTUnwrap(settings["rules"] as? [[String: Any]])
        for i in rules.indices { rules[i].removeValue(forKey: "pauseWhenIdle") }
        settings["rules"] = rules; object["settings"] = settings
        let decoded = try JSONDecoder().decode(ProgressDocument.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.tasks, original.tasks); XCTAssertEqual(decoded.journal, original.journal)
        XCTAssertEqual(decoded.sessions, original.sessions)
        XCTAssertEqual(decoded.settings.rules, original.settings.rules)
        XCTAssertTrue(decoded.outcomes.isEmpty); XCTAssertFalse(decoded.gitTracking.enabled)
        XCTAssertFalse(decoded.outcomeGoals.isEmpty)
    }
    func testGoalsUseCalendarPeriodsAndEndIsExclusive() {
        var document = ProgressDocument()
        document.outcomes = [
            .init(category: .english, metric: .lessons, quantity: 2, date: day(12)),
            .init(category: .english, metric: .lessons, quantity: 3, date: day(13)),
            .init(category: .learning, metric: .lessons, quantity: 7, date: day(13))
        ]
        let stats = OutcomeStatistics(document: document, calendar: calendar)
        XCTAssertEqual(stats.progress(.init(category: .english, metric: .lessons, target: 5), now: day(13)), 5)
        XCTAssertEqual(stats.progress(.init(category: .english, metric: .lessons, target: 5, period: .daily), now: day(13)), 3)
        let interval = DateInterval(start: day(12), end: day(13))
        XCTAssertEqual(stats.quantity(metric: .lessons, category: .english, in: interval), 2)
    }
    func testTasksAndJournalAreDerivedAndUpdatesDoNotDuplicateResults() {
        var document = ProgressDocument()
        let task = ProgressTask(title: "Task", category: .english, completedAt: day(13))
        document.tasks = [task]
        document.journal = [.init(category: "Psychology", text: "My own note", createdAt: day(13)),
                            .init(category: "Psychology", text: "AI-рефлексія\nGenerated", createdAt: day(13))]
        let stats = OutcomeStatistics(document: document, calendar: calendar)
        XCTAssertEqual(stats.quantity(metric: .completedTasks), 1)
        XCTAssertEqual(stats.quantity(metric: .completedTasks, category: .programming), 0)
        XCTAssertEqual(stats.quantity(metric: .journalEntries), 1)
        document.tasks[0].completedAt = nil
        XCTAssertEqual(OutcomeStatistics(document: document).quantity(metric: .completedTasks), 0)
        XCTAssertTrue(document.outcomes.isEmpty)
    }
    func testGitMergeDeduplicatesAcrossRepositoriesAndCompletesOnlyExplicitTask() {
        var document = ProgressDocument()
        document.gitTracking.completeReferencedTasks = true
        let task = ProgressTask(title: "Ship a feature", category: .programming, createdAt: day(12))
        document.tasks = [task]
        let hash = String(repeating: "a", count: 40)
        let commit = GitCommit(hash: hash, date: day(13), subject: "Done \(OutcomeAutomation.taskCode(task.id))")
        XCTAssertEqual(OutcomeAutomation.mergeCommits([commit, commit], into: &document, now: day(14)), 1)
        XCTAssertEqual(document.tasks[0].completedAt, day(13))
        XCTAssertEqual(document.outcomes.count, 1)
        document.tasks[0].completedAt = nil
        XCTAssertEqual(OutcomeAutomation.mergeCommits([commit], into: &document, now: day(14)), 0)
        XCTAssertNil(document.tasks[0].completedAt) // A manually reopened task is not re-closed by the same event.
    }
    func testOrdinaryOldAndDisabledCommitsNeverCloseTasks() {
        var document = ProgressDocument()
        let task = ProgressTask(title: "Feature", category: .programming, createdAt: day(13))
        document.tasks = [task]
        let message = "Fixes \(OutcomeAutomation.taskCode(task.id))"
        _ = OutcomeAutomation.mergeCommits([.init(hash: String(repeating: "a", count: 40), date: day(14), subject: message)], into: &document, now: day(15))
        XCTAssertNil(document.tasks[0].completedAt)
        document.gitTracking.completeReferencedTasks = true
        _ = OutcomeAutomation.mergeCommits([.init(hash: String(repeating: "b", count: 40), date: day(12), subject: message),
                                           .init(hash: String(repeating: "c", count: 40), date: day(14), subject: "Some work \(OutcomeAutomation.taskCode(task.id))")], into: &document, now: day(15))
        XCTAssertNil(document.tasks[0].completedAt)
    }
    func testAmbiguousTaskCodeIsNotCompleted() {
        let first = ProgressTask(id: UUID(uuidString: "12345678-0000-0000-0000-000000000001")!, title: "A", category: .programming)
        let second = ProgressTask(id: UUID(uuidString: "12345678-0000-0000-0000-000000000002")!, title: "B", category: .programming)
        XCTAssertNil(OutcomeAutomation.referencedTask(in: "Done MP-12345678", tasks: [first, second]))
    }
    func testGitParserFiltersAuthorsDatesAndRejectsMalformedOutput() throws {
        let hash = String(repeating: "f", count: 40)
        let raw = "\(hash)\u{1f}\(Int(day(13).timeIntervalSince1970))\u{1f}me@example.test\u{1f}A result\u{1e}\n"
        XCTAssertEqual(try GitReader.parse(raw, authorEmail: "ME@example.test", since: day(12)).count, 1)
        XCTAssertTrue(try GitReader.parse(raw, authorEmail: "other@example.test", since: day(12)).isEmpty)
        XCTAssertTrue(try GitReader.parse(raw, authorEmail: "me@example.test", since: day(14)).isEmpty)
        XCTAssertThrowsError(try GitReader.parse("bad\u{1e}", authorEmail: "me@example.test", since: day(12)))
    }
    func testCSVHandlesQuotesNewlinesAndRepeatedImports() throws {
        let csv = """
        source,external_id,date,category,metric,quantity,note
        lesson-service,one,2026-10-13T10:00:00Z,english,words,12,"Words, and \"\"phrases\"\""
        lesson-service,two,2026-10-13T11:00:00Z,english,exercises,2,"Line one
        Line two"
        """
        let records = try OutcomeCSV.read(csv, now: day(14))
        XCTAssertEqual(records[0].note, "Words, and \"phrases\"")
        XCTAssertEqual(records[1].note, "Line one\nLine two")
        var document = ProgressDocument()
        XCTAssertEqual(OutcomeAutomation.merge(records, into: &document), 2)
        XCTAssertEqual(OutcomeAutomation.merge(try OutcomeCSV.read(csv, now: day(14)), into: &document), 0)
        XCTAssertEqual(document.outcomes.count, 2)
    }
    func testCSVRejectsDerivedMetricsWrongCategoryAndInvalidDate() {
        let header = "source,external_id,date,category,metric,quantity,note\n"
        for row in ["s,id,2026-10-13T10:00:00Z,english,completedTasks,1,note",
                    "s,id,2026-10-13T10:00:00Z,sport,words,1,note",
                    "s,id,2026-10-13T10:00:00Z,english,words,0,note",
                    "s,id,2100-10-13T10:00:00Z,english,words,1,note"] {
            XCTAssertThrowsError(try OutcomeCSV.read(header + row, now: day(14)))
        }
        XCTAssertThrowsError(try OutcomeCSV.read(header + "\"unclosed", now: day(14)))
    }
    func testChatGPTReportSupportsMarkdownAndStableEventIDs() throws {
        let json = #"{"id":"lesson-1","date":"2026-10-13T10:00:00Z","category":"english","summary":"Past tense","results":[{"metric":"words","quantity":10},{"metric":"exercises","quantity":2}]}"#
        let records = try LearningReport.read("```json\n\(json)\n```", now: day(14))
        XCTAssertEqual(records.map(\.quantity), [10, 2])
        var document = ProgressDocument()
        XCTAssertEqual(OutcomeAutomation.merge(records, into: &document), 2)
        XCTAssertEqual(OutcomeAutomation.merge(try LearningReport.read(json, now: day(14)), into: &document), 0)
        XCTAssertEqual(OutcomeStatistics(document: document).quantity(metric: .words), 10)
    }
    func testChatGPTReportCannotInventTaskCompletionOrDuplicateMetrics() {
        for results in [#"[{"metric":"completedTasks","quantity":1}]"#,
                        #"[{"metric":"words","quantity":1},{"metric":"words","quantity":2}]"#,
                        #"[{"metric":"words","quantity":0}]"#] {
            let json = "{\"id\":\"lesson\",\"date\":\"2026-10-13T10:00:00Z\",\"category\":\"english\",\"summary\":\"Note\",\"results\":\(results)}"
            XCTAssertThrowsError(try LearningReport.read(json, now: day(14)))
        }
    }
    func testResultGoalsUnlockAchievementsWithoutAnyTimeSession() {
        var document = ProgressDocument()
        document.outcomeGoals = [.init(category: .programming, metric: .commits, target: 1)]
        _ = OutcomeAutomation.mergeCommits([.init(hash: String(repeating: "a", count: 40), date: day(13), subject: "Result")], into: &document, now: day(14))
        AchievementDefinition.update(&document, now: day(13), calendar: calendar)
        XCTAssertTrue(document.achievements.contains { $0.id == "first-git" })
        XCTAssertTrue(document.achievements.contains { $0.id == "result-goal" })
    }
    func testInvalidResultDataAndDuplicateReferencesAreRejected() {
        let repo = DocumentRepository(url: URL(fileURLWithPath: "/unused"))
        var document = ProgressDocument()
        document.outcomes = [.init(category: .sport, metric: .words, quantity: 1)]
        XCTAssertThrowsError(try repo.validate(document))
        document.outcomes = [.init(category: .programming, metric: .commits, quantity: 2, source: .git, reference: "git:hash")]
        XCTAssertThrowsError(try repo.validate(document))
        document.outcomes = [1, 2].map { _ in .init(category: .english, metric: .words, quantity: 1, source: .imported, reference: "same") }
        XCTAssertThrowsError(try repo.validate(document))
    }
    func testActualLocalGitReaderWithTwoAuthorsAndEmptyRepository() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func git(_ args: [String]) throws {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", folder.path, "-c", "user.name=Test Learner", "-c", "commit.gpgSign=false", "-c", "core.hooksPath=/dev/null"] + args
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        }
        try git(["init"]); try git(["config", "user.email", "me@example.test"])
        var repo = try GitReader.inspect(path: folder.path)
        XCTAssertTrue(try GitReader.commits(repository: repo, since: Date().addingTimeInterval(-3600)).isEmpty)
        try git(["commit", "--allow-empty", "-m", "My result"])
        try git(["-c", "user.email=other@example.test", "commit", "--allow-empty", "-m", "Other result"])
        XCTAssertEqual(try GitReader.commits(repository: repo, since: Date().addingTimeInterval(-3600)).map(\.subject), ["My result"])
        repo.authorEmail = "other@example.test"
        XCTAssertEqual(try GitReader.commits(repository: repo, since: Date().addingTimeInterval(-3600)).map(\.subject), ["Other result"])
    }
    func testUpgradeCreatesByteExactBackupAndThenDoesNotBackUpVersionTwo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = DocumentRepository(url: directory.appendingPathComponent("progress.json"))
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ProgressDocument())) as? [String: Any])
        raw["version"] = 1
        let original = try JSONSerialization.data(withJSONObject: raw)
        try original.write(to: repo.url)
        let loaded = try XCTUnwrap(repo.load())
        XCTAssertEqual(loaded.version, 2)
        let backup = try XCTUnwrap(repo.backupVersionOneIfNeeded())
        XCTAssertEqual(try Data(contentsOf: backup), original)
        try repo.save(loaded)
        XCTAssertNil(try repo.backupVersionOneIfNeeded())
    }

}
