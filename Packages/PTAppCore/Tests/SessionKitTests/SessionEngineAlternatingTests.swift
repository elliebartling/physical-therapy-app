import XCTest
import DataKit
@testable import SessionKit

@MainActor
final class SessionEngineAlternatingTests: XCTestCase {
    func test_alternating_flipsLeftRight() async throws {
        let ex = Exercise(name: "Side leg raise", target: .repsSets(reps: 10, sets: 4),
                          restSeconds: 0, side: .alternating, order: 0)
        let routine = Routine(name: "T", exercises: [ex])
        let engine = SessionEngine(routine: routine, clock: TestClock())

        var sides: [Side] = []
        let collector = Task {
            for await e in engine.events {
                if case .setStarted(_, _, let s) = e { sides.append(s) }
            }
        }
        let run = Task { try await engine.start() }
        try await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<4 {
            try await engine.completeCurrentSet()
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await run.value
        try await Task.sleep(nanoseconds: 20_000_000)
        collector.cancel()

        XCTAssertEqual(sides, [.left, .right, .left, .right])
    }
}
