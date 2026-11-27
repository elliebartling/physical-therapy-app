import XCTest
import DataKit
@testable import SessionKit

@MainActor
final class SessionEngineTransitionTests: XCTestCase {
    private func routine() -> (Routine, Exercise, Exercise) {
        let plank = Exercise(name: "Plank", target: .timeSets(seconds: 30, sets: 1), restSeconds: 0, side: .both, order: 0)
        let wallSit = Exercise(name: "Wall sit", target: .timeSets(seconds: 30, sets: 1), restSeconds: 0, side: .both, order: 1)
        return (Routine(name: "T", exercises: [plank, wallSit]), plank, wallSit)
    }

    private func transitions(in events: [PhaseEvent]) -> [PhaseEvent] {
        events.filter { if case .transition = $0 { true } else { false } }
    }

    func test_aTimedPause_comesBetweenExercises_notAfterTheLast() async throws {
        let (routine, _, wallSit) = routine()
        let engine = SessionEngine(routine: routine, clock: TestClock(), transition: .timed(seconds: 10))

        var events: [PhaseEvent] = []
        let collector = Task { for await e in engine.events { events.append(e) } }
        try await engine.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        collector.cancel()

        XCTAssertEqual(transitions(in: events), [.transition(nextExerciseID: wallSit.id, seconds: 10)])
        XCTAssertEqual(events.last, .sessionCompleted)
    }

    func test_waitingForMe_holdsUntilStarted() async throws {
        let (routine, _, wallSit) = routine()
        let engine = SessionEngine(routine: routine, clock: TestClock(), transition: .manual)

        var events: [PhaseEvent] = []
        let collector = Task { for await e in engine.events { events.append(e) } }
        let run = Task { try await engine.start() }
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(events.last, .transition(nextExerciseID: wallSit.id, seconds: nil), "waits for a tap")

        try await engine.completeCurrentSet()
        try await run.value
        try await Task.sleep(nanoseconds: 50_000_000)
        collector.cancel()
        XCTAssertEqual(events.last, .sessionCompleted)
    }

    func test_noPause_goesStraightOn() async throws {
        let (routine, _, _) = routine()
        let engine = SessionEngine(routine: routine, clock: TestClock())

        var events: [PhaseEvent] = []
        let collector = Task { for await e in engine.events { events.append(e) } }
        try await engine.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        collector.cancel()

        XCTAssertTrue(transitions(in: events).isEmpty)
    }

    func test_transitionSettings() {
        XCTAssertEqual(SessionTransition(seconds: -1), .none)
        XCTAssertEqual(SessionTransition(seconds: 0), .manual)
        XCTAssertEqual(SessionTransition(seconds: 15), .timed(seconds: 15))
        XCTAssertEqual(SessionTransition.resolve(routineSeconds: nil, appSeconds: 10), .timed(seconds: 10))
        XCTAssertEqual(SessionTransition.resolve(routineSeconds: 0, appSeconds: 10), .manual, "the routine's own wins")
        XCTAssertEqual(SessionTransition.title(for: 0), "Wait for me")
        XCTAssertEqual(SessionTransition.title(for: -1), "No pause")
        XCTAssertEqual(SessionTransition.title(for: 20), "20 seconds")
    }
}
