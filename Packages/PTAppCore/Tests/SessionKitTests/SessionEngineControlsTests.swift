import XCTest
import DataKit
@testable import SessionKit

@MainActor
final class SessionEngineControlsTests: XCTestCase {
    func test_pauseEmitsPaused_resumeEmitsResumed() async throws {
        // Use reps×sets so the engine awaits the test's input — gives pause()
        // a deterministic window to register before set completion.
        let ex = Exercise(name: "Wall sit", target: .repsSets(reps: 10, sets: 2),
                          restSeconds: 0, side: .both, order: 0)
        let routine = Routine(name: "T", exercises: [ex])
        let engine = SessionEngine(routine: routine, clock: TestClock())

        var events: [PhaseEvent] = []
        let collector = Task { for await e in engine.events { events.append(e) } }

        let run = Task { try await engine.start() }
        try await Task.sleep(nanoseconds: 50_000_000)
        // Engine is blocked on completeCurrentSet for set 0. Pause now;
        // the awaitIfPaused at top of the next iteration will trigger.
        engine.pause()
        try await engine.completeCurrentSet()  // unblocks set 0; next iteration hits paused
        try await Task.sleep(nanoseconds: 50_000_000)
        engine.resume()
        try await Task.sleep(nanoseconds: 50_000_000)
        try await engine.completeCurrentSet()  // ends set 1 → session completes

        try await run.value
        try await Task.sleep(nanoseconds: 50_000_000)
        collector.cancel()

        XCTAssertTrue(events.contains(.paused))
        XCTAssertTrue(events.contains(.resumed))
    }

    func test_skipMovesThroughEachSet() async throws {
        let ex = Exercise(name: "Squat", target: .repsSets(reps: 10, sets: 3),
                          restSeconds: 5, side: .both, order: 0)
        let routine = Routine(name: "T", exercises: [ex])
        let engine = SessionEngine(routine: routine, clock: TestClock())

        var setStartCount = 0
        let collector = Task {
            for await e in engine.events {
                if case .setStarted = e { setStartCount += 1 }
            }
        }
        let run = Task { try await engine.start() }
        try await Task.sleep(nanoseconds: 20_000_000)
        try await engine.skipCurrentSet()
        try await Task.sleep(nanoseconds: 20_000_000)
        try await engine.skipCurrentSet()
        try await Task.sleep(nanoseconds: 20_000_000)
        try await engine.skipCurrentSet()
        try await run.value
        try await Task.sleep(nanoseconds: 20_000_000)
        collector.cancel()
        XCTAssertEqual(setStartCount, 3)
    }
}
