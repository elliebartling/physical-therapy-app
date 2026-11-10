import XCTest
import DataKit
@testable import SessionKit

@MainActor
final class SessionEngineRepsSetsTests: XCTestCase {
    func test_singleExerciseTwoSets_emitsExpectedEvents() async throws {
        let exerciseID = UUID()
        let exercise = Exercise(
            id: exerciseID,
            name: "Squat",
            target: .repsSets(reps: 10, sets: 2),
            restSeconds: 5,
            side: .both,
            order: 0
        )
        let routine = Routine(name: "Test", exercises: [exercise])

        let clock = TestClock()
        let engine = SessionEngine(routine: routine, clock: clock)
        var events: [PhaseEvent] = []
        let collector = Task { for await event in engine.events { events.append(event) } }

        let run = Task { try await engine.start() }
        try await Task.sleep(nanoseconds: 50_000_000)
        try await engine.completeCurrentSet()  // ends set 1
        try await Task.sleep(nanoseconds: 50_000_000)
        try await engine.completeCurrentSet()  // ends set 2 → exercise completes → session completes
        try await run.value
        try await Task.sleep(nanoseconds: 50_000_000)
        collector.cancel()

        XCTAssertEqual(events.first, .sessionStarted)
        XCTAssertEqual(events[1], .exerciseStarted(exerciseID: exerciseID, index: 0, totalExercises: 1))
        XCTAssertTrue(events.contains(.setStarted(setIndex: 0, totalSets: 2, side: .both)))
        XCTAssertTrue(events.contains(.rest(seconds: 5)))
        XCTAssertTrue(events.contains(.setStarted(setIndex: 1, totalSets: 2, side: .both)))
        XCTAssertTrue(events.contains(.exerciseCompleted(exerciseID: exerciseID)))
        XCTAssertEqual(events.last, .sessionCompleted)
    }
}
