import XCTest
import SwiftData
import DataKit
import HistoryKit
@testable import UI

@MainActor
final class ProgressViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var routineRepo: RoutineRepository!
    private var sessionRepo: SessionRepository!
    private var routine: Routine!

    private let calendar = Calendar.current
    private func day(_ d: Int, month: Int = 11, hour: Int = 9, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: d, hour: hour, minute: minute))!
    }
    private var today: Date { day(11, hour: 15) }
    private var bridges: Exercise { routine.orderedExercises[0] }
    private var wallSit: Exercise { routine.orderedExercises[1] }

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

    private func viewModel() -> ProgressViewModel {
        let vm = ProgressViewModel(routineRepo: routineRepo, sessionRepo: sessionRepo, today: today)
        vm.refresh()
        return vm
    }

    /// A guided session: timed, only completed exercises recorded.
    @discardableResult
    private func guided(start: Date, minutes: Double, done: [Exercise]) throws -> SessionRecord {
        let end = start.addingTimeInterval(minutes * 60)
        let record = SessionRecord(routineID: routine.id, startedAt: start, completedAt: end, exerciseRecords:
            done.map { ExerciseRecord(exerciseID: $0.id, status: .completed, startedAt: start, completedAt: end) })
        try sessionRepo.insert(record)
        return record
    }

    /// A logged session: no timing; skipped exercises recorded as skipped.
    @discardableResult
    private func logged(at date: Date, done: [Exercise], skipped: [Exercise]) throws -> SessionRecord {
        let records = done.map { ExerciseRecord(exerciseID: $0.id, status: .completed, startedAt: date, completedAt: date) }
            + skipped.map { ExerciseRecord(exerciseID: $0.id, status: .skipped, startedAt: date) }
        let record = SessionRecord(routineID: routine.id, startedAt: date,
                                   completedAt: skipped.isEmpty ? date : nil, exerciseRecords: records)
        try sessionRepo.insert(record)
        return record
    }

    func test_noSessions_showsTheEmptyState_withExercisesNotDoneYet() {
        let vm = viewModel()
        XCTAssertFalse(vm.hasSessions)
        XCTAssertEqual(vm.activeDays, 0)
        XCTAssertEqual(vm.exercises.map(\.name), ["Bridges", "Wall sit"])
        XCTAssertEqual(vm.exercises.map(\.stats), [ExerciseStats(), ExerciseStats()])
    }

    func test_consistency_countsActiveDaysAndTheStreak() throws {
        try guided(start: day(10), minutes: 12, done: [bridges, wallSit])
        try guided(start: day(11), minutes: 10, done: [bridges, wallSit])
        try logged(at: day(9, hour: 12), done: [bridges], skipped: [wallSit])   // partial: not an active day

        let vm = viewModel()

        XCTAssertEqual(vm.weeks.count, ProgressViewModel.weeksShown)
        XCTAssertEqual(vm.activeDays, 2)
        XCTAssertEqual(vm.streak, 2)
    }

    func test_exercises_showHowOftenEachWasDoneOrSkipped() throws {
        try guided(start: day(10), minutes: 12, done: [bridges, wallSit])
        try logged(at: day(9, hour: 12), done: [bridges], skipped: [wallSit])

        let vm = viewModel()

        XCTAssertEqual(vm.exercise(id: bridges.id)?.stats.completed, 2)
        XCTAssertEqual(vm.exercise(id: wallSit.id)?.stats, ExerciseStats(completed: 1, skipped: 1,
                                                                        lastDone: day(10).addingTimeInterval(12 * 60)))
        XCTAssertEqual(vm.entries(forExercise: wallSit.id).map(\.isDone), [true, false], "newest first")
    }

    func test_history_groupsByMonthNewestFirst_andTellsTimedFromLogged() throws {
        let timed = try guided(start: day(10), minutes: 12.2, done: [bridges, wallSit])
        let log = try logged(at: day(9, hour: 12), done: [bridges], skipped: [wallSit])
        try guided(start: day(28, month: 10), minutes: 8, done: [bridges])

        let vm = viewModel()

        XCTAssertEqual(vm.months.count, 2)
        XCTAssertEqual(vm.months.first?.sessions.map(\.id), [timed.id, log.id])
        let timedRow = try XCTUnwrap(vm.session(id: timed.id))
        XCTAssertEqual(timedRow.minutes, 12)
        XCTAssertTrue(timedRow.isComplete)
        let logRow = try XCTUnwrap(vm.session(id: log.id))
        XCTAssertNil(logRow.minutes, "a logged session has no timing")
        XCTAssertFalse(logRow.isComplete)
        XCTAssertEqual(logRow.items.map(\.name), ["Bridges", "Wall sit"])
        XCTAssertEqual(logRow.items.map(\.isDone), [true, false])
        XCTAssertEqual(logRow.doneCount, 1)
    }

    func test_anExerciseNoLongerInAnyRoutine_isStillListed() throws {
        let gone = UUID()
        try sessionRepo.insert(SessionRecord(routineID: routine.id, startedAt: day(10), completedAt: day(10),
            exerciseRecords: [ExerciseRecord(exerciseID: gone, status: .completed, startedAt: day(10), completedAt: day(10))]))

        let vm = viewModel()

        XCTAssertEqual(vm.months.first?.sessions.first?.items.map(\.name), ["Removed exercise"])
    }

    func test_deletingASession_removesItFromHistoryAndTheCounts() throws {
        try guided(start: day(10), minutes: 12, done: [bridges, wallSit])
        let mistake = try guided(start: day(11), minutes: 10, done: [bridges, wallSit])
        let vm = viewModel()
        XCTAssertEqual(vm.activeDays, 2)

        XCTAssertTrue(vm.deleteSession(id: mistake.id))

        XCTAssertNil(vm.session(id: mistake.id))
        XCTAssertEqual(vm.activeDays, 1)
        XCTAssertEqual(try sessionRepo.fetchAll().count, 1)
        XCTAssertFalse(vm.deleteSession(id: UUID()), "an unknown session isn't deleted")
    }
}
