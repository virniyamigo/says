import XCTest
@testable import MyProgressCore

final class MyProgressCoreTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    func testSessionsAcrossMidnightAreSplitAndLegacyTimeIsNotDated() {
        var document = ProgressDocument()
        document.sessions = [.init(category: .programming, startedAt: date(10, hour: 23, minute: 30), endedAt: date(11, minute: 30))]
        document.legacyTotals = [.init(category: .programming, seconds: 7200)]
        let stats = ProgressStatistics(document: document, calendar: calendar)
        XCTAssertEqual(stats.total(), 10800)
        XCTAssertEqual(stats.today(category: .programming, now: date(10)), 1800)
        XCTAssertEqual(stats.today(now: date(11)), 1800)
        XCTAssertEqual(stats.today(category: .sport, now: date(11)), 0)
        XCTAssertEqual(stats.days(count: 2, ending: date(11)).map(\.seconds), [1800, 1800])
    }
    func testDaylightSavingUsesCalendarDayInsteadOfFixed24Hours() {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 25))!
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        var document = ProgressDocument()
        document.sessions = [.init(category: .learning, startedAt: start, endedAt: end)]
        XCTAssertEqual(ProgressStatistics(document: document, calendar: cal).today(now: start), 25 * 3600)
    }
    func testStreakAllowsUnfinishedTodayButStopsAtGap() {
        var document = ProgressDocument()
        document.sessions = [7, 8, 9].map { day in
            .init(category: .english, startedAt: date(day), endedAt: date(day, minute: 2))
        }
        XCTAssertEqual(ProgressStatistics(document: document, calendar: calendar).streak(now: date(10)), 3)
        XCTAssertEqual(ProgressStatistics(document: document, calendar: calendar).streak(now: date(11)), 0)
    }
    func testRecorderHasOneSessionAndSwitchesTaskWithoutDoubleCounting() {
        var document = ProgressDocument()
        var recorder = SessionRecorder()
        let start = date(10)
        let taskID = UUID()
        recorder.observe(document: &document, category: .programming, now: start)
        recorder.observe(document: &document, category: .programming, now: start.addingTimeInterval(2))
        recorder.observe(document: &document, category: .english, taskID: taskID, now: start.addingTimeInterval(4))
        recorder.stop(document: &document, now: start.addingTimeInterval(5))
        XCTAssertNil(document.activeSessionID)
        XCTAssertEqual(document.sessions.count, 2)
        XCTAssertEqual(document.sessions[0].duration, 4)
        XCTAssertEqual(document.sessions[1].duration, 1)
        XCTAssertEqual(ProgressStatistics(document: document).taskSeconds(taskID), 1)
    }
    func testIdleAndSleepGapsDoNotAccumulateTime() {
        var document = ProgressDocument()
        var recorder = SessionRecorder()
        let start = date(10)
        recorder.observe(document: &document, category: .sport, now: start)
        recorder.observe(document: &document, category: .sport, now: start.addingTimeInterval(1))
        recorder.observe(document: &document, category: nil, now: start.addingTimeInterval(2))
        recorder.observe(document: &document, category: .sport, now: start.addingTimeInterval(1000))
        recorder.observe(document: &document, category: .sport, now: start.addingTimeInterval(1001))
        recorder.stop(document: &document, now: start.addingTimeInterval(1001))
        XCTAssertEqual(document.sessions.reduce(0) { $0 + $1.duration }, 2)
    }
    func testUnobservedGapClosesCheckpointAndStartsFreshSession() {
        var document = ProgressDocument()
        var recorder = SessionRecorder()
        let start = date(10)
        recorder.observe(document: &document, category: .learning, now: start)
        recorder.observe(document: &document, category: .learning, now: start.addingTimeInterval(1))
        recorder.observe(document: &document, category: .learning, now: start.addingTimeInterval(3600))
        XCTAssertEqual(document.sessions.count, 2)
        XCTAssertEqual(document.sessions[0].duration, 1)
        XCTAssertEqual(document.sessions[1].duration, 0)
    }
    func testBackwardClockChangeDoesNotProduceNegativeDuration() {
        var document = ProgressDocument()
        var recorder = SessionRecorder()
        let start = date(10)
        recorder.observe(document: &document, category: .learning, now: start)
        recorder.observe(document: &document, category: .learning, now: start.addingTimeInterval(-2))
        XCTAssertTrue(document.sessions.allSatisfy { $0.duration >= 0 })
    }
    func testMigrationKeepsOriginalNotesAndTotalsWithoutChangingDefaults() throws {
        let suite = "MyProgress-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let note = JournalEntry(category: "Psychology", text: "Старий запис", createdAt: date(10))
        defaults.set(4200, forKey: "programming.totalTime")
        defaults.set(try JSONEncoder().encode([note]), forKey: "myprogress.journal.entries.v1")
        let document = try DocumentRepository.migrate(defaults: defaults)
        XCTAssertEqual(document.journal, [note])
        XCTAssertEqual(document.legacyTotals, [.init(category: .programming, seconds: 4200)])
        XCTAssertTrue(document.sessions.isEmpty)
        XCTAssertEqual(defaults.double(forKey: "programming.totalTime"), 4200)
    }
    func testCorruptLegacyJournalDoesNotSilentlyDisappear() {
        let suite = "MyProgress-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: "myprogress.journal.entries.v1")
        XCTAssertThrowsError(try DocumentRepository.migrate(defaults: defaults))
    }
    func testDocumentRoundTripAndUnreadableFileRemainsUntouched() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = DocumentRepository(url: folder.appendingPathComponent("progress.json"))
        XCTAssertNil(try repo.load())
        var document = ProgressDocument()
        document.tasks = [.init(title: "Вивчити Swift", category: .programming)]
        try repo.save(document)
        XCTAssertEqual(try repo.load(), document)
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: repo.url)
        XCTAssertThrowsError(try repo.load())
        XCTAssertEqual(try Data(contentsOf: repo.url), corrupt)
    }
    func testUnsupportedVersionInvalidDurationAndDuplicateIDsAreRejected() throws {
        let repo = DocumentRepository(url: URL(fileURLWithPath: "/unused"))
        var document = ProgressDocument()
        document.version = 3
        XCTAssertThrowsError(try repo.validate(document))
        document.version = 2
        let session = ActivitySession(category: .sport, startedAt: date(11), endedAt: date(10))
        document.sessions = [session]
        XCTAssertThrowsError(try repo.validate(document))
        document.sessions = []
        let task = ProgressTask(title: "Task", category: .english)
        document.tasks = [task, task]
        XCTAssertThrowsError(try repo.validate(document))
    }
    func testAchievementsUnlockOnceAndRemainAfterEditingHistory() {
        var document = ProgressDocument()
        document.tasks = [.init(title: "Done", category: .learning, completedAt: date(10))]
        document.journal = [.init(category: "Psychology", text: "Note")]
        AchievementDefinition.update(&document, now: date(10), calendar: calendar)
        AchievementDefinition.update(&document, now: date(11), calendar: calendar)
        XCTAssertEqual(Set(document.achievements.map(\.id)), ["first-task", "first-note"])
        XCTAssertTrue(document.achievements.allSatisfy { $0.unlockedAt == date(10) })
        document.tasks = []; document.journal = []
        AchievementDefinition.update(&document)
        XCTAssertEqual(document.achievements.count, 2)
    }
    func testFirstMinuteAchievementIncludesMultipleShortSessions() {
        var document = ProgressDocument()
        document.sessions = [10, 11].map { day in
            .init(category: .programming, startedAt: date(day), endedAt: date(day).addingTimeInterval(30))
        }
        AchievementDefinition.update(&document, now: date(11), calendar: calendar)
        XCTAssertTrue(document.achievements.contains { $0.id == "first-session" })
    }
    func testIncompleteGoalsAndBlankTasksAreRejectedOnRestore() {
        let repo = DocumentRepository(url: URL(fileURLWithPath: "/unused"))
        var document = ProgressDocument()
        document.goals = []
        XCTAssertThrowsError(try repo.validate(document))
        document = ProgressDocument()
        document.tasks = [.init(title: "  ", category: .english)]
        XCTAssertThrowsError(try repo.validate(document))
    }
    func testTimeFormattingHandlesInvalidAndVeryLargeInput() {
        XCTAssertEqual(TimeText.clock(3661), "01:01:01")
        XCTAssertEqual(TimeText.short(-2), "0 год 0 хв")
        XCTAssertEqual(TimeText.clock(.infinity), "—")
        XCTAssertEqual(TimeText.short(.nan), "—")
        XCTAssertFalse(TimeText.short(Double.greatestFiniteMagnitude).isEmpty)
    }

}
