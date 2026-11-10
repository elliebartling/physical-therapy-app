import XCTest
import DataKit
import SessionKit
@testable import UI

@MainActor
final class SessionViewModelTests: XCTestCase {
    func test_runToCompletion_persistsSessionRecord() async throws {
        let container = try ModelContainerFactory.inMemory()
        let routineRepo = RoutineRepository(context: container.mainContext)
        let sessionRepo = SessionRepository(context: container.mainContext)

        let routine = Routine(name: "T", exercises: [
            Exercise(name: "X", target: .timeSets(seconds: 1, sets: 1), restSeconds: 0, side: .both, order: 0)
        ])
        try routineRepo.save(routine)

        let clock = TestClock()
        let vm = SessionViewModel(routine: routine, sessionRepo: sessionRepo, clock: clock,
                                  audio: nil, haptics: nil)
        await vm.run()
        try await Task.sleep(nanoseconds: 50_000_000) // drain final events
        XCTAssertEqual(try sessionRepo.fetchAll().count, 1)
        XCTAssertNotNil(try sessionRepo.fetchAll().first?.completedAt)

        _ = container // keep alive
    }

    func test_endEarly_savesPartialSession_andRunDoesNotMarkItComplete() async throws {
        let container = try ModelContainerFactory.inMemory()
        let routineRepo = RoutineRepository(context: container.mainContext)
        let sessionRepo = SessionRepository(context: container.mainContext)

        let routine = Routine(name: "T", exercises: [
            Exercise(name: "X", target: .timeSets(seconds: 1, sets: 1), restSeconds: 0, side: .both, order: 0)
        ])
        try routineRepo.save(routine)

        let vm = SessionViewModel(routine: routine, sessionRepo: sessionRepo, clock: TestClock(),
                                  audio: nil, haptics: nil)
        vm.endEarly()

        XCTAssertTrue(vm.isComplete)
        XCTAssertTrue(vm.endedEarly)
        XCTAssertEqual(try sessionRepo.fetchAll().count, 1)
        XCTAssertNil(try sessionRepo.fetchAll().first?.completedAt)

        _ = container
    }

    func test_timedSet_showsHoldWithItsDuration() async throws {
        let container = try ModelContainerFactory.inMemory()
        let sessionRepo = SessionRepository(context: container.mainContext)
        let routine = Routine(name: "T", exercises: [
            Exercise(name: "Plank", target: .timeSets(seconds: 30, sets: 1), restSeconds: 0, side: .both, order: 0)
        ])

        let vm = SessionViewModel(routine: routine, sessionRepo: sessionRepo, clock: TestClock(),
                                  audio: nil, haptics: nil)
        await vm.run()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(vm.display, .hold(seconds: 30))
        XCTAssertEqual(vm.currentExerciseName, "Plank")
        XCTAssertEqual(vm.totalExercises, 1)

        _ = container
    }
}

final class TimerReadingTests: XCTestCase {
    func test_hold_drainsWithElapsedTime() {
        let start = Date(timeIntervalSince1970: 0)
        let reading = TimerReading(display: .hold(seconds: 30), startedAt: start,
                                   now: start.addingTimeInterval(12))
        XCTAssertEqual(reading.remaining, 18)
        XCTAssertEqual(reading.fraction, 0.6, accuracy: 0.0001)
    }

    func test_hold_neverGoesNegative() {
        let start = Date(timeIntervalSince1970: 0)
        let reading = TimerReading(display: .rest(seconds: 15), startedAt: start,
                                   now: start.addingTimeInterval(40))
        XCTAssertEqual(reading.remaining, 0)
        XCTAssertEqual(reading.fraction, 0)
    }

    func test_reps_showsCountWithNoField() {
        let reading = TimerReading(display: .reps(10), startedAt: .now, now: .now)
        XCTAssertEqual(reading.remaining, 10)
        XCTAssertEqual(reading.fraction, 0)
    }
}
