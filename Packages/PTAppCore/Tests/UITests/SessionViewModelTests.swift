import XCTest
import DataKit
import SessionKit
import SwiftUI
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

    func test_currentArtIsTheFirstExercisesArtBeforeTheSessionRuns() throws {
        let container = try ModelContainerFactory.inMemory()
        let sessionRepo = SessionRepository(context: container.mainContext)
        let routine = Routine(name: "T", exercises: [
            Exercise(name: "Bird Dog", target: .repsSets(reps: 10, sets: 1), restSeconds: 0,
                     side: .both, order: 0, art: .library(slug: "bird-dog")),
            Exercise(name: "Plank", target: .timeSets(seconds: 30, sets: 1), restSeconds: 0,
                     side: .both, order: 1, art: ArtChoice.none),
        ])
        let vm = SessionViewModel(routine: routine, sessionRepo: sessionRepo, clock: TestClock(),
                                  audio: nil, haptics: nil)
        XCTAssertEqual(vm.currentArt, .library(slug: "bird-dog"))
        _ = container
    }


    func test_currentArtFollowsTheSessionToTheNextExercise() async throws {
        let container = try ModelContainerFactory.inMemory()
        let sessionRepo = SessionRepository(context: container.mainContext)
        let routine = Routine(name: "T", exercises: [
            Exercise(name: "Bird Dog", target: .timeSets(seconds: 5, sets: 1), restSeconds: 0,
                     side: .both, order: 0, art: .library(slug: "bird-dog")),
            Exercise(name: "Plank", target: .timeSets(seconds: 5, sets: 1), restSeconds: 0,
                     side: .both, order: 1, art: ArtChoice.none),
        ])
        let vm = SessionViewModel(routine: routine, sessionRepo: sessionRepo, clock: TestClock(),
                                  audio: nil, haptics: nil)
        await vm.run()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(vm.currentExerciseName, "Plank")
        XCTAssertEqual(vm.currentArt, ArtChoice.none)
        _ = container
    }

    func test_figureShowsOnlyForLibraryArtWhileExercisingAtNormalSizes() {
        let lib = ArtChoice.library(slug: "bird-dog")
        XCTAssertTrue(SessionView.showsFigure(art: lib, isResting: false, dynamicTypeSize: .large))
        XCTAssertFalse(SessionView.showsFigure(art: lib, isResting: true, dynamicTypeSize: .large))
        XCTAssertFalse(SessionView.showsFigure(art: lib, isResting: false, dynamicTypeSize: .accessibility1))
        XCTAssertFalse(SessionView.showsFigure(art: ArtChoice.none, isResting: false, dynamicTypeSize: .large))
        XCTAssertFalse(SessionView.showsFigure(art: .unmatched, isResting: false, dynamicTypeSize: .large))
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

@MainActor
final class SessionPauseTests: XCTestCase {
    func test_pause_holdsTheTimerStill_andResumeCarriesOn() async throws {
        let container = try ModelContainerFactory.inMemory()
        let sessionRepo = SessionRepository(context: container.mainContext)
        let routine = Routine(name: "T", exercises: [
            Exercise(name: "Wall sit", target: .timeSets(seconds: 30, sets: 1), restSeconds: 0, side: .both, order: 0)
        ])
        let vm = SessionViewModel(routine: routine, sessionRepo: sessionRepo, clock: ManualClock(),
                                  audio: nil, haptics: nil, health: nil)
        let run = Task { await vm.run() }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(vm.display, .hold(seconds: 30))
        let startedAt = vm.displayStartedAt

        vm.pause()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNotNil(vm.pausedAt)
        XCTAssertTrue(vm.isPaused)
        // While paused the reading is taken at the pause, however long it lasts.
        let held = TimerReading(display: vm.display, startedAt: vm.displayStartedAt,
                                now: vm.pausedAt ?? .now)
        XCTAssertEqual(held.remaining, 30)

        try await Task.sleep(nanoseconds: 300_000_000)
        vm.resume()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(vm.pausedAt)
        // Paused for at least 0.3s, so the start moves on by at least that much.
        XCTAssertGreaterThanOrEqual(vm.displayStartedAt.timeIntervalSince(startedAt), 0.3)
        XCTAssertLessThan(vm.displayStartedAt.timeIntervalSince(startedAt),
                          Date.now.timeIntervalSince(startedAt))

        run.cancel()
        _ = container
    }
}
