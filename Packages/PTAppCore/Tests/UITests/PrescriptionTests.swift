import XCTest
import DataKit
@testable import UI

final class PrescriptionTests: XCTestCase {
    func test_reps() {
        XCTAssertEqual(Prescription.text(target: .repsSets(reps: 10, sets: 3), side: .both), "3×10")
    }

    func test_timed_withAlternatingSides() {
        XCTAssertEqual(Prescription.text(target: .timeSets(seconds: 20, sets: 3), side: .alternating), "3×20s L/R")
    }

    func test_singleSide() {
        XCTAssertEqual(Prescription.text(target: .repsSets(reps: 8, sets: 2), side: .left), "2×8 L")
        XCTAssertEqual(Prescription.text(target: .repsSets(reps: 8, sets: 2), side: .right), "2×8 R")
    }
}

@MainActor
final class SessionEstimateTests: XCTestCase {
    func test_empty_isZero() {
        XCTAssertEqual(SessionEstimate.minutes(for: []), 0)
    }

    func test_countsWorkAndRestBetweenSetsOnly() {
        // 3 × 30s hold with 30s rest → 90s work + 60s rest = 150s → 3 min (rounded up).
        let plank = Exercise(name: "Plank", target: .timeSets(seconds: 30, sets: 3), restSeconds: 30, side: .both)
        XCTAssertEqual(SessionEstimate.minutes(for: [plank]), 3)
    }

    func test_repsCountAtThreeSecondsEach() {
        // 2 × 10 reps = 60s, no rest → 1 min.
        let bridges = Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 2), restSeconds: 0, side: .both)
        XCTAssertEqual(SessionEstimate.minutes(for: [bridges]), 1)
    }

    func test_alternating_countsEverySetOnBothSides() {
        let ex = Exercise(name: "Side plank", target: .timeSets(seconds: 30, sets: 3),
                          restSeconds: 30, side: .alternating, order: 0)
        // 3 sets × 2 sides × 30s + 2 rests × 30s = 240s
        XCTAssertEqual(SessionEstimate.minutes(for: [ex]), 4)
    }
}
