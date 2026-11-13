import XCTest
import DataKit
@testable import SessionKit

@MainActor
final class SessionEngineAlternatingTests: XCTestCase {
    func test_alternating_doesEverySetOnTheLeftThenTheRight() async throws {
        let ex = Exercise(name: "Side leg raise", target: .repsSets(reps: 10, sets: 2),
                          restSeconds: 0, side: .alternating, order: 0)
        let routine = Routine(name: "T", exercises: [ex])
        let engine = SessionEngine(routine: routine, clock: TestClock())

        var sets: [(Int, Side)] = []
        var switches: [Side] = []
        let collector = Task {
            for await e in engine.events {
                if case .setStarted(let index, _, let side) = e { sets.append((index, side)) }
                if case .sideSwitch(let side) = e { switches.append(side) }
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

        XCTAssertEqual(sets.map(\.0), [0, 0, 1, 1])
        XCTAssertEqual(sets.map(\.1), [.left, .right, .left, .right])
        XCTAssertEqual(switches, [.right, .right])
    }

    func test_alternatingHold_restsOnlyBetweenFullSets() async throws {
        let ex = Exercise(name: "Side plank", target: .timeSets(seconds: 20, sets: 3),
                          restSeconds: 30, side: .alternating, order: 0)
        let engine = SessionEngine(routine: Routine(name: "T", exercises: [ex]), clock: TestClock())

        var log: [String] = []
        let collector = Task {
            for await e in engine.events {
                switch e {
                case .setStarted(_, _, let side): log.append(side == .left ? "L" : "R")
                case .rest: log.append("rest")
                default: break
                }
            }
        }
        try await engine.start()
        try await Task.sleep(nanoseconds: 20_000_000)
        collector.cancel()

        XCTAssertEqual(log, ["L", "R", "rest", "L", "R", "rest", "L", "R"])
    }

    func test_oneSidedExercise_isUnchanged() async throws {
        let ex = Exercise(name: "Clamshell", target: .repsSets(reps: 10, sets: 2),
                          restSeconds: 0, side: .left, order: 0)
        let engine = SessionEngine(routine: Routine(name: "T", exercises: [ex]), clock: TestClock())
        var sides: [Side] = []
        let collector = Task {
            for await e in engine.events { if case .setStarted(_, _, let s) = e { sides.append(s) } }
        }
        let run = Task { try await engine.start() }
        try await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<2 {
            try await engine.completeCurrentSet()
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await run.value
        try await Task.sleep(nanoseconds: 20_000_000)
        collector.cancel()
        XCTAssertEqual(sides, [.left, .left])
    }
}
