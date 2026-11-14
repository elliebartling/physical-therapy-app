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
    private var defaults: UserDefaults!
    private var suiteName = ""

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
        suiteName = "ProgressViewModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        routine = nil; sessionRepo = nil; routineRepo = nil; container = nil; defaults = nil
    }

    private func viewModel() -> ProgressViewModel {
        let vm = ProgressViewModel(routineRepo: routineRepo, sessionRepo: sessionRepo, defaults: defaults, today: today)
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

        XCTAssertEqual(vm.weeks.count, 13, "three months by default")
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

    func test_aNewPhase_continuesHistoryForExercisesWithTheSameName() throws {
        try guided(start: day(9), minutes: 10, done: [bridges, wallSit])
        let oldBridges = bridges
        try routineRepo.replaceActive(with: Routine(name: "Knee", exercises: [
            Exercise(name: "Bridges", target: .repsSets(reps: 15, sets: 3), restSeconds: 30, side: .both, order: 0),
            Exercise(name: "Step ups", target: .repsSets(reps: 10, sets: 2), restSeconds: 30, side: .both, order: 1),
        ]))
        let phase2 = try XCTUnwrap(routineRepo.fetchActive())
        let newBridges = phase2.orderedExercises[0]
        let session = SessionRecord(routineID: phase2.id, startedAt: day(10), completedAt: day(10), exerciseRecords: [
            ExerciseRecord(exerciseID: newBridges.id, status: .completed, startedAt: day(10), completedAt: day(10))
        ])
        try sessionRepo.insert(session)

        let vm = viewModel()

        XCTAssertEqual(vm.exercises.map(\.name), ["Bridges", "Step ups"])
        XCTAssertEqual(vm.exercises.first?.stats.completed, 2)
        XCTAssertEqual(vm.exercises.last?.stats.completed, 0)
        XCTAssertEqual(vm.entries(forExercise: newBridges.id).count, 2)
        // The removed exercise still reads by name in the older session.
        let older = try XCTUnwrap(vm.months.first?.sessions.last)
        XCTAssertTrue(older.items.map(\.name).contains("Wall sit"))
        XCTAssertNotEqual(oldBridges.id, newBridges.id)
    }

    // MARK: Analytics

    /// A guided session where each exercise got the given rating, with optional pain.
    @discardableResult
    private func rated(on date: Date, _ ratings: KeyValuePairs<Exercise, ExerciseRating?>, pain: Int? = nil,
                       note: String? = nil) throws -> SessionRecord {
        let end = date.addingTimeInterval(10 * 60)
        let records = ratings.map { exercise, rating in
            let record = ExerciseRecord(exerciseID: exercise.id, status: .completed, startedAt: date, completedAt: end)
            record.rating = rating
            return record
        }
        let session = SessionRecord(routineID: routine.id, startedAt: date, completedAt: end, exerciseRecords: records)
        session.painLevel = pain
        session.note = note
        try sessionRepo.insert(session)
        return session
    }

    func test_range_changesTheWeeksCovered_andTheHeatmapStaysLegible() throws {
        try guided(start: day(1, month: 1), minutes: 10, done: [bridges])
        let vm = viewModel()

        vm.range = .fourWeeks
        XCTAssertEqual(vm.weeks.count, 4)
        XCTAssertEqual(vm.heatmap.count, 4)

        vm.range = .all
        XCTAssertGreaterThan(vm.weeks.count, 40, "back to the first session in January")
        XCTAssertEqual(vm.heatmap.count, 26, "the heatmap caps at half a year")
    }

    func test_weeklyGoal_drivesTheHeadline_andIsRemembered() throws {
        try guided(start: day(9), minutes: 10, done: [bridges, wallSit])    // Monday
        try guided(start: day(10), minutes: 10, done: [bridges, wallSit])
        let vm = viewModel()
        XCTAssertEqual(vm.weeklyGoal, ProgressViewModel.defaultWeeklyGoal)
        XCTAssertEqual(vm.daysThisWeek, 2)

        vm.weeklyGoal = 2
        XCTAssertEqual(vm.goalStatus, .met)
        XCTAssertEqual(viewModel().weeklyGoal, 2, "remembered for next time")

        vm.weeklyGoal = 7
        if case .behind(let remaining) = vm.goalStatus {
            XCTAssertEqual(remaining, 5)
        } else if vm.goalStatus != .onTrack {
            XCTFail("2 of 7 can't be met yet")
        }
    }

    func test_minutesAndPain_coverTheRange() throws {
        try rated(on: day(20, month: 10), [bridges: nil], pain: 5)
        try rated(on: day(5), [bridges: nil], pain: 3)
        try logged(at: day(9, hour: 12), done: [bridges], skipped: [])

        let vm = viewModel()

        XCTAssertEqual(vm.minutes, 20, "two timed sessions; the logged one has no minutes")
        XCTAssertEqual(vm.painNow, 3)
        XCTAssertEqual(vm.painFrom, 5)
        XCTAssertEqual(vm.painPoints.map(\.level), [5, 3])
    }

    func test_anExerciseRatedHardLately_isWorthTellingYourPT() throws {
        try rated(on: day(2), [bridges: .aboutRight, wallSit: .aboutRight])
        try rated(on: day(4), [bridges: .aboutRight, wallSit: .aboutRight])
        try rated(on: day(6), [bridges: .hard, wallSit: .aboutRight])
        try rated(on: day(8), [bridges: .painful, wallSit: .easy])
        try rated(on: day(10), [bridges: .hard, wallSit: .aboutRight])

        let vm = viewModel()

        let row = try XCTUnwrap(vm.exercise(id: bridges.id))
        XCTAssertEqual(row.trend, .harder(count: 3, of: 4, before: .aboutRight))
        XCTAssertEqual(row.recent, [.rated(.aboutRight), .rated(.aboutRight), .rated(.hard), .rated(.painful), .rated(.hard)])
        let insight = try XCTUnwrap(vm.insight(forExercise: bridges.id))
        XCTAssertEqual(insight.title, "Bridges — Harder lately")
        XCTAssertEqual(insight.detail, "Rated hard or painful 3 of the last 4 times, after mostly “about right”.")
        XCTAssertNil(vm.insight(forExercise: wallSit.id))
        XCTAssertEqual(ProgressViewModel.flag(for: .harder(count: 3, of: 4, before: nil)), "↑ Harder")
    }

    func test_painGoingDown_isWorthTellingYourPT() throws {
        try rated(on: day(14, month: 10), [bridges: nil], pain: 5)
        try rated(on: day(20, month: 10), [bridges: nil], pain: 4)
        try rated(on: day(2), [bridges: nil], pain: 2)
        try rated(on: day(10), [bridges: nil], pain: 1)

        let vm = viewModel()

        let pain = try XCTUnwrap(vm.insights.first { $0.exerciseID == nil })
        XCTAssertEqual(pain.title, "Pain — down")
        XCTAssertEqual(pain.detail, "Average pain after sessions was 1.5 over the last two weeks, down from 4.5 the four weeks before.")
    }

    func test_marks_showSkippedAndUnratedTimes() throws {
        try logged(at: day(9, hour: 12), done: [bridges], skipped: [wallSit])
        try rated(on: day(10), [wallSit: .easy])

        let vm = viewModel()

        XCTAssertEqual(vm.marks(forExercise: wallSit.id, count: 12), [.skipped, .rated(.easy)])
        XCTAssertEqual(vm.marks(forExercise: bridges.id, count: 12), [.done])
        XCTAssertEqual(MarkStrip.spoken([.skipped, .rated(.easy), .done]), "Last 3 times: 1 easy, 1 not rated, 1 skipped")
    }

    func test_phases_showWhatWasPrescribedEachTime() throws {
        try guided(start: day(2), minutes: 10, done: [bridges])
        try routineRepo.replaceActive(with: Routine(name: "Knee", exercises: [
            Exercise(name: "Bridges", target: .repsSets(reps: 15, sets: 3), restSeconds: 30, side: .both, order: 0),
        ]))
        let newBridges = try XCTUnwrap(routineRepo.fetchActive()?.orderedExercises.first)
        try sessionRepo.insert(SessionRecord(routineID: UUID(), startedAt: day(10), completedAt: day(10), exerciseRecords: [
            ExerciseRecord(exerciseID: newBridges.id, status: .completed, startedAt: day(10), completedAt: day(10))
        ]))

        let vm = viewModel()

        let phases = vm.phases(forExercise: newBridges.id)
        XCTAssertEqual(phases.map(\.prescription), ["3×10", "3×15"])
        XCTAssertEqual(phases.map(\.number), [1, 2])
        XCTAssertNotNil(phases.first?.end)
        XCTAssertNil(phases.last?.end, "the current phase is open-ended")
        XCTAssertEqual(vm.entries(forExercise: newBridges.id).map(\.prescription), ["3×15", "3×10"])
    }

    func test_visitSummary_coversTheRangeForYourPT() throws {
        try rated(on: day(6), [bridges: .hard, wallSit: .aboutRight], pain: 4)
        try rated(on: day(8), [bridges: .painful, wallSit: .aboutRight], pain: 3, note: "Left hip clicks on the way up")
        try rated(on: day(10), [bridges: .hard, wallSit: .easy], pain: 2)

        let vm = viewModel()
        vm.range = .fourWeeks
        let summary = vm.visitSummary()

        XCTAssertTrue(summary.hasPrefix("PT summary — Knee"))
        XCTAssertTrue(summary.contains("3 days with a full session in 4 weeks (goal 5 a week"))
        XCTAssertTrue(summary.contains("30 minutes of guided sessions"))
        XCTAssertTrue(summary.contains("• Latest 2, first in this period 4 (3 readings)"))
        XCTAssertTrue(summary.contains("• Bridges — Harder lately: Rated hard or painful 3 of the last 3 times."))
        XCTAssertTrue(summary.contains("• Bridges (3×10): done 3. Felt: 2 hard, 1 painful"))
        XCTAssertTrue(summary.contains("• Wall sit (3×30s): done 3. Felt: 1 easy, 2 about right"))
        XCTAssertTrue(summary.contains("Left hip clicks on the way up"))
    }
}
