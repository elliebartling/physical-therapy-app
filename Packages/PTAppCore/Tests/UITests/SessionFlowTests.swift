import XCTest
import SwiftData
import DataKit
import HistoryKit
import ParsingKit
import SessionKit
@testable import UI

@MainActor
final class SessionFlowTests: XCTestCase {
    private var container: ModelContainer!
    private var routineRepo: RoutineRepository!
    private var sessionRepo: SessionRepository!
    private var routine: Routine!

    private let calendar = Calendar.current
    private func day(_ d: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }
    private var today: Date { day(11, hour: 15) }
    private var bridges: Exercise { routine.orderedExercises[0] }
    private var clams: Exercise { routine.orderedExercises[1] }
    private var extra: Exercise { routine.orderedExercises[2] }

    override func setUp() async throws {
        container = try ModelContainerFactory.inMemory()
        routineRepo = RoutineRepository(context: container.mainContext)
        sessionRepo = SessionRepository(context: container.mainContext)
        routine = Routine(name: "Hips", exercises: [
            Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 2), restSeconds: 30, side: .both, order: 0),
            Exercise(name: "Clams", target: .repsSets(reps: 15, sets: 2), restSeconds: 30, side: .both, order: 1),
            Exercise(name: "Extra", target: .timeSets(seconds: 30, sets: 1), restSeconds: 0, side: .both, order: 2,
                     isOptional: true),
        ])
        try routineRepo.save(routine)
    }

    override func tearDown() async throws {
        routine = nil; sessionRepo = nil; routineRepo = nil; container = nil
    }

    private func home() async -> HomeViewModel {
        let vm = HomeViewModel(routineRepo: routineRepo, sessionRepo: sessionRepo, otherWorkouts: nil, today: today)
        await vm.refresh()
        return vm
    }

    // MARK: Continuing later the same day

    func test_aSessionEndedEarly_canBeContinuedLaterToday() async throws {
        try sessionRepo.insert(SessionRecord(routineID: routine.id, startedAt: day(11, hour: 7), exerciseRecords: [
            ExerciseRecord(exerciseID: bridges.id, status: .completed, startedAt: day(11, hour: 7)),
        ]))

        let vm = await home()

        XCTAssertEqual(vm.startInfo?.title, "Continue session")
        XCTAssertEqual(vm.rows.map(\.isDone), [true, false, false])
        XCTAssertEqual(vm.remainingCount, 2)
        XCTAssertFalse(vm.isDoneToday)
    }

    func test_aCompleteDay_startsAgainFromTheTop() async throws {
        try sessionRepo.insert(SessionRecord(routineID: routine.id, startedAt: day(11, hour: 7),
                                             completedAt: day(11, hour: 7), exerciseRecords: [
            ExerciseRecord(exerciseID: bridges.id, status: .completed, startedAt: day(11, hour: 7)),
        ]))

        let vm = await home()

        XCTAssertEqual(vm.startInfo?.title, "Start again")
        XCTAssertEqual(vm.rows.map(\.isDone), [false, false, false])
    }

    // MARK: Optional exercises

    func test_finishingWithOnlyOptionalExercisesLeft_completesTheDay() throws {
        let vm = SessionViewModel(routine: routine, sessionRepo: sessionRepo, clock: TestClock(),
                                  audio: nil, haptics: nil, health: nil, skipping: [bridges.id, clams.id],
                                  countdownHaptics: false)

        XCTAssertTrue(vm.canFinishNow)
        vm.finishNow()

        XCTAssertTrue(vm.isComplete)
        XCTAssertFalse(vm.endedEarly, "it's a finish, so the completion screen shows")
        XCTAssertNotNil(try sessionRepo.fetchAll().first?.completedAt)
        XCTAssertTrue(DayProgress.isComplete(on: .now, in: try sessionRepo.fetchAll()))
    }

    func test_finishingIsOnlyOffered_onceEveryRequiredExerciseIsDone() {
        let vm = SessionViewModel(routine: routine, sessionRepo: sessionRepo, clock: TestClock(),
                                  audio: nil, haptics: nil, health: nil, skipping: [bridges.id], countdownHaptics: false)
        XCTAssertFalse(vm.canFinishNow)
        vm.finishNow()
        XCTAssertFalse(vm.isComplete)
    }

    func test_loggingWithoutTheOptionalOne_stillCountsAsComplete() throws {
        let log = LogSessionViewModel(routine: routine, sessionRepo: sessionRepo, date: day(10), now: today, health: nil)
        log.setDone(false, for: extra.id)

        XCTAssertTrue(log.isComplete)
        XCTAssertTrue(log.save())
        XCTAssertNotNil(try sessionRepo.fetchAll().first?.completedAt)
    }

    func test_todayMarksOptionalRows() async {
        let vm = await home()
        XCTAssertEqual(vm.rows.map(\.isOptional), [false, false, true])
    }

    func test_optionalExercises_areNotFlaggedForBeingSkipped() {
        XCTAssertNil(ProgressViewModel.trend(.oftenSkipped(count: 4), isOptional: true))
        XCTAssertEqual(ProgressViewModel.trend(.oftenSkipped(count: 4), isOptional: false), .oftenSkipped(count: 4))
        XCTAssertEqual(ProgressViewModel.trend(.easier(count: 3, of: 4), isOptional: true), .easier(count: 3, of: 4))
    }

    func test_optionalSurvivesEditingAndANewSheet() throws {
        var draft = ParsedRoutine(routine: routine)
        XCTAssertEqual(draft.exercises.map(\.isOptional), [false, false, true])
        draft.exercises[0].isOptional = true
        draft.apply(to: routine)
        XCTAssertTrue(bridges.isOptional)

        try routineRepo.replaceActive(with: Routine(name: "Hips", exercises: [
            Exercise(name: "Bridges", target: .repsSets(reps: 12, sets: 3), restSeconds: 30, side: .both, order: 0),
        ]))
        XCTAssertEqual(try routineRepo.fetchActive()?.orderedExercises.first?.isOptional, true,
                       "a new sheet keeps what the person marked")
    }

    // MARK: Countdown haptics

    func test_countdownTicks_onTheLastThreeSecondsOfAHoldOrRest() {
        let hold = SessionViewModel.Display.hold(seconds: 30)
        XCTAssertTrue(SessionViewModel.isCountdownTick(display: hold, isPaused: false, from: 4, to: 3))
        XCTAssertTrue(SessionViewModel.isCountdownTick(display: .rest(seconds: 20), isPaused: false, from: 2, to: 1))
        XCTAssertFalse(SessionViewModel.isCountdownTick(display: hold, isPaused: false, from: 5, to: 4))
        XCTAssertFalse(SessionViewModel.isCountdownTick(display: hold, isPaused: false, from: 1, to: 0), "the end has its own")
        XCTAssertFalse(SessionViewModel.isCountdownTick(display: hold, isPaused: true, from: 3, to: 2))
        XCTAssertFalse(SessionViewModel.isCountdownTick(display: .reps(10), isPaused: false, from: 3, to: 2))
    }

    func test_countdownHaptics_areOnUntilTurnedOff() {
        let name = "SessionFlowTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(SessionPreferences.countdownHaptics(in: defaults))
        defaults.set(false, forKey: SessionPreferences.countdownHapticsKey)
        XCTAssertFalse(SessionPreferences.countdownHaptics(in: defaults))
    }
}
