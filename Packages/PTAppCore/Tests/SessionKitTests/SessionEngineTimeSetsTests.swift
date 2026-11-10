import XCTest
import DataKit
@testable import SessionKit

@MainActor
final class SessionEngineTimeSetsTests: XCTestCase {
    func test_timeSets_autoAdvancesViaClock() async throws {
        let plank = Exercise(
            name: "Plank",
            target: .timeSets(seconds: 30, sets: 2),
            restSeconds: 10,
            side: .both,
            order: 0
        )
        let routine = Routine(name: "T", exercises: [plank])
        let engine = SessionEngine(routine: routine, clock: TestClock())

        var events: [PhaseEvent] = []
        let collector = Task { for await e in engine.events { events.append(e) } }
        try await engine.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        collector.cancel()

        XCTAssertEqual(events.last, .sessionCompleted)
        XCTAssertEqual(events.filter { if case .setStarted = $0 { true } else { false } }.count, 2)
        XCTAssertEqual(events.filter { if case .rest = $0 { true } else { false } }.count, 1) // no rest after last set
    }
}
