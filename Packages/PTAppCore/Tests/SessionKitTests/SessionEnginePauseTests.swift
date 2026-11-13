import XCTest
import DataKit
@testable import SessionKit

/// Pausing must stop a hold or rest that's already counting, and resuming carries on from what was left.
@MainActor
final class SessionEnginePauseTests: XCTestCase {
    private var events: [PhaseEvent] = []
    private var collector: Task<Void, Never>?

    override func tearDown() async throws {
        collector?.cancel()
        collector = nil
        events = []
    }

    private func settle() async throws { try await Task.sleep(nanoseconds: 30_000_000) }

    private func start(_ exercise: Exercise, clock: ManualClock) -> (SessionEngine, Task<Void, Error>) {
        let engine = SessionEngine(routine: Routine(name: "T", exercises: [exercise]), clock: clock)
        collector = Task { for await e in engine.events { self.events.append(e) } }
        let run = Task { try await engine.start() }
        return (engine, run)
    }

    private var finished: Bool { events.contains(.sessionCompleted) }

    func test_pausingAHold_stopsItsCount_andResumeCarriesOnWithWhatWasLeft() async throws {
        let clock = ManualClock()
        let (engine, run) = start(Exercise(name: "Wall sit", target: .timeSets(seconds: 30, sets: 1),
                                           restSeconds: 0, side: .both, order: 0), clock: clock)
        try await settle()
        clock.advance(by: 10)
        try await settle()

        engine.pause()
        try await settle()
        clock.advance(by: 100)        // a long pause: the hold must not end
        try await settle()
        XCTAssertFalse(finished)

        engine.resume()
        try await settle()
        clock.advance(by: 19)
        try await settle()
        XCTAssertFalse(finished, "20 seconds were left at the pause")

        clock.advance(by: 1)
        try await run.value
        try await settle()
        XCTAssertTrue(finished)
    }

    func test_pausingARest_stopsItsCount() async throws {
        let clock = ManualClock()
        let (engine, run) = start(Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 2),
                                           restSeconds: 30, side: .both, order: 0), clock: clock)
        try await settle()
        try await engine.completeCurrentSet()   // set 1 done → rest
        try await settle()
        XCTAssertTrue(events.contains(.rest(seconds: 30)))

        engine.pause()
        try await settle()
        clock.advance(by: 60)
        try await settle()
        XCTAssertEqual(events.filter { if case .setStarted = $0 { true } else { false } }.count, 1,
                       "the rest shouldn't run out while paused")

        engine.resume()
        try await settle()
        clock.advance(by: 30)
        try await settle()
        XCTAssertEqual(events.filter { if case .setStarted = $0 { true } else { false } }.count, 2)

        try await engine.completeCurrentSet()
        try await run.value
    }

    func test_skippingWhilePaused_endsTheHoldOnResume() async throws {
        let clock = ManualClock()
        let (engine, run) = start(Exercise(name: "Plank", target: .timeSets(seconds: 30, sets: 1),
                                           restSeconds: 0, side: .both, order: 0), clock: clock)
        try await settle()
        engine.pause()
        try await settle()
        try await engine.skipCurrentSet()
        try await settle()
        XCTAssertFalse(finished)

        engine.resume()
        try await run.value
        try await settle()
        XCTAssertTrue(finished)
    }
}
