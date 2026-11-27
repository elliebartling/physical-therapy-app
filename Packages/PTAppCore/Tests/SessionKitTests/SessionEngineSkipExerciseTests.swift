import XCTest
import DataKit
@testable import SessionKit

@MainActor
final class SessionEngineSkipExerciseTests: XCTestCase {
    func test_skippingAnExercise_leavesTheRestOfItOut_andMovesOn() async throws {
        let extra = Exercise(name: "Extra", target: .repsSets(reps: 10, sets: 3), restSeconds: 0, side: .both, order: 0)
        let plank = Exercise(name: "Plank", target: .timeSets(seconds: 30, sets: 1), restSeconds: 0, side: .both, order: 1)
        let engine = SessionEngine(routine: Routine(name: "T", exercises: [extra, plank]), clock: TestClock())

        var events: [PhaseEvent] = []
        let collector = Task { for await e in engine.events { events.append(e) } }
        let run = Task { try await engine.start() }
        try await Task.sleep(nanoseconds: 50_000_000)   // waiting on the first reps set
        try await engine.skipCurrentExercise()
        try await run.value
        try await Task.sleep(nanoseconds: 50_000_000)
        collector.cancel()

        XCTAssertTrue(events.contains(.exerciseSkipped(exerciseID: extra.id)))
        XCTAssertFalse(events.contains(.exerciseCompleted(exerciseID: extra.id)))
        XCTAssertTrue(events.contains(.exerciseCompleted(exerciseID: plank.id)))
        let extraSets = events.filter { if case .setStarted = $0 { true } else { false } }.count
        XCTAssertEqual(extraSets, 2, "one set of the extra, then the plank's")
        XCTAssertEqual(events.last, .sessionCompleted)
    }
}
