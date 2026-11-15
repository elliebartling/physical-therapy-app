import XCTest
import DataKit
@testable import SessionKit

@MainActor
final class SessionEngineSkippingTests: XCTestCase {
    func test_skippedExercises_areLeftOutOfTheSession() async throws {
        let plank = Exercise(name: "Plank", target: .timeSets(seconds: 30, sets: 1), restSeconds: 0, side: .both, order: 0)
        let stretch = Exercise(name: "Stretch", target: .timeSets(seconds: 30, sets: 1), restSeconds: 0, side: .both, order: 1)
        let wallSit = Exercise(name: "Wall sit", target: .timeSets(seconds: 30, sets: 1), restSeconds: 0, side: .both, order: 2)
        let routine = Routine(name: "T", exercises: [plank, stretch, wallSit])
        let engine = SessionEngine(routine: routine, clock: TestClock(), skipping: [stretch.id])

        var events: [PhaseEvent] = []
        let collector = Task { for await e in engine.events { events.append(e) } }
        try await engine.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        collector.cancel()

        let started = events.compactMap { event -> (UUID, Int)? in
            if case let .exerciseStarted(id, _, total) = event { return (id, total) }
            return nil
        }
        XCTAssertEqual(started.map(\.0), [plank.id, wallSit.id])
        XCTAssertEqual(started.map(\.1), [2, 2], "the count leaves the covered exercise out too")
        XCTAssertEqual(events.last, .sessionCompleted)
    }
}
