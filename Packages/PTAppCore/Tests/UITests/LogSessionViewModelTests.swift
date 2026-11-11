import XCTest
import SwiftData
import DataKit
import HistoryKit
@testable import UI

@MainActor
final class LogSessionViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var routineRepo: RoutineRepository!
    private var sessionRepo: SessionRepository!
    private var routine: Routine!

    private let calendar = Calendar.current
    // A Wednesday afternoon, so the rest of the week is in reach.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 15))!
    }
    private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: now)! }

    override func setUp() async throws {
        container = try ModelContainerFactory.inMemory()
        routineRepo = RoutineRepository(context: container.mainContext)
        sessionRepo = SessionRepository(context: container.mainContext)
        routine = Routine(name: "Knee", exercises: [
            Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both, order: 0),
            Exercise(name: "Wall sit", target: .timeSets(seconds: 30, sets: 3), restSeconds: 30, side: .both, order: 1),
        ])
        try routineRepo.save(routine)
    }

    override func tearDown() async throws {
        routine = nil; sessionRepo = nil; routineRepo = nil; container = nil
    }

    func test_loggingEveryExercise_fillsThatDayAndExtendsTheStreak() throws {
        let vm = LogSessionViewModel(routine: routine, sessionRepo: sessionRepo, date: yesterday, now: now)
        XCTAssertTrue(vm.items.allSatisfy(\.isDone), "every exercise starts checked")

        XCTAssertTrue(vm.save())

        let sessions = try sessionRepo.fetchAll()
        XCTAssertEqual(sessions.count, 1)
        let week = WeekStrip.forWeek(containing: now, sessions: sessions)
        let yesterdayStart = calendar.startOfDay(for: yesterday)
        XCTAssertEqual(week.days.first { $0.date == yesterdayStart }?.isCompleted, true)
        XCTAssertFalse(week.isTodayCompleted)
        XCTAssertEqual(StreakCalculator.currentStreak(in: sessions, today: now), 1)
        XCTAssertEqual(sessions[0].routineID, routine.id)
        XCTAssertEqual(sessions[0].exerciseRecords.map(\.status), [.completed, .completed])
    }

    func test_uncheckingAnExercise_keepsItAsPartial_whichDoesNotFillTheDay() throws {
        let vm = LogSessionViewModel(routine: routine, sessionRepo: sessionRepo, date: yesterday, now: now)
        vm.items[1].isDone = false
        XCTAssertFalse(vm.isEveryExerciseDone)

        XCTAssertTrue(vm.save())

        let sessions = try sessionRepo.fetchAll()
        XCTAssertEqual(sessions.count, 1, "a partial log is still kept")
        XCTAssertFalse(sessions[0].isComplete)
        let statuses = Dictionary(uniqueKeysWithValues: sessions[0].exerciseRecords.map { ($0.exerciseID, $0.status) })
        XCTAssertEqual(statuses[routine.orderedExercises[0].id], .completed)
        XCTAssertEqual(statuses[routine.orderedExercises[1].id], .skipped)
        XCTAssertEqual(WeekStrip.forWeek(containing: now, sessions: sessions).completedCount, 0)
    }

    func test_nothingChecked_cannotBeSaved() throws {
        let vm = LogSessionViewModel(routine: routine, sessionRepo: sessionRepo, date: yesterday, now: now)
        for index in vm.items.indices { vm.items[index].isDone = false }

        XCTAssertFalse(vm.canSave)
        XCTAssertFalse(vm.save())
        XCTAssertTrue(try sessionRepo.fetchAll().isEmpty)
    }

    func test_aFutureDay_isClampedToToday() throws {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let vm = LogSessionViewModel(routine: routine, sessionRepo: sessionRepo, date: tomorrow, now: now)

        XCTAssertTrue(vm.save())

        let session = try XCTUnwrap(try sessionRepo.fetchAll().first)
        XCTAssertTrue(calendar.isDate(session.startedAt, inSameDayAs: now))
        XCTAssertTrue(WeekStrip.forWeek(containing: now, sessions: [session]).isTodayCompleted)
    }

    func test_homeOffersALog_onlyWhenThereIsARoutine() async throws {
        let home = HomeViewModel(routineRepo: routineRepo, sessionRepo: sessionRepo, today: now)
        XCTAssertEqual(home.logSession(on: yesterday)?.items.map(\.name), ["Bridges", "Wall sit"])

        let empty = try ModelContainerFactory.inMemory()
        let emptyHome = HomeViewModel(routineRepo: RoutineRepository(context: empty.mainContext),
                                      sessionRepo: SessionRepository(context: empty.mainContext),
                                      today: now)
        XCTAssertNil(emptyHome.logSession(on: yesterday))
        _ = empty
    }
}
