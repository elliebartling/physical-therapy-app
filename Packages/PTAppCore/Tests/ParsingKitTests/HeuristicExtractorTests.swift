import XCTest
import DataKit
@testable import ParsingKit

final class HeuristicExtractorTests: XCTestCase {
    private func parse(_ lines: [String]) async throws -> [ParsedRoutine.ParsedExercise] {
        try await HeuristicExtractor().extract(fromOCRLines: lines).exercises
    }

    // Quantity patterns

    func test_setsXReps() async throws {
        let ex = try await parse(["Squats 3 x 10"])[0]
        XCTAssertEqual(ex.name, "Squats")
        XCTAssertEqual(ex.sets, 3)
        XCTAssertEqual(ex.reps, 10)
        XCTAssertNil(ex.durationSec)
    }

    func test_setsOfReps() async throws {
        let ex = try await parse(["Bridges 3 sets of 12"])[0]
        XCTAssertEqual(ex.name, "Bridges")
        XCTAssertEqual(ex.sets, 3)
        XCTAssertEqual(ex.reps, 12)
    }

    func test_bareReps_defaultsSets() async throws {
        let ex = try await parse(["Clamshells x15"])[0]
        XCTAssertEqual(ex.name, "Clamshells")
        XCTAssertEqual(ex.sets, 3)
        XCTAssertEqual(ex.reps, 15)
    }

    func test_timedHold() async throws {
        let ex = try await parse(["Plank hold 30 sec"])[0]
        XCTAssertEqual(ex.name, "Plank")
        XCTAssertEqual(ex.durationSec, 30)
        XCTAssertNil(ex.reps)
    }

    func test_setsXDuration() async throws {
        let ex = try await parse(["Wall sit 3 x 45 sec"])[0]
        XCTAssertEqual(ex.name, "Wall sit")
        XCTAssertEqual(ex.sets, 3)
        XCTAssertEqual(ex.durationSec, 45)
        XCTAssertNil(ex.reps)
    }

    func test_minutesConvertToSeconds() async throws {
        let ex = try await parse(["Hamstring stretch 2 min"])[0]
        XCTAssertEqual(ex.durationSec, 120)
    }

    // Rest

    func test_restSeconds() async throws {
        let ex = try await parse(["Squats 3 x 10 rest 45 sec"])[0]
        XCTAssertEqual(ex.restSec, 45)
        XCTAssertEqual(ex.reps, 10)
        XCTAssertEqual(ex.name, "Squats")
    }

    func test_restDefaults30() async throws {
        let ex = try await parse(["Squats 3 x 10"])[0]
        XCTAssertEqual(ex.restSec, 30)
    }

    // Sides

    func test_eachSide_mapsToBoth_andStripsMarker() async throws {
        let ex = try await parse(["Leg raises 3 x 10 each side"])[0]
        XCTAssertEqual(ex.side, "both")
        XCTAssertEqual(ex.name, "Leg raises")
    }

    func test_alternating() async throws {
        let ex = try await parse(["Alternating lunges 3 x 10"])[0]
        XCTAssertEqual(ex.side, "alternating")
    }

    func test_singleSide() async throws {
        let ex = try await parse(["Left leg raises 3 x 10"])[0]
        XCTAssertEqual(ex.side, "left")
        XCTAssertEqual(ex.name, "leg raises")
    }

    // Furniture + floor

    func test_furnitureLinesDropped() async throws {
        let exs = try await parse([
            "Lakeview Physical Therapy - www.lakeviewpt.com",
            "Printed 06/14/2026",
            "Page 1",
            "(555) 123-4567",
            "Squats 3 x 10",
        ])
        XCTAssertEqual(exs.count, 1)
        XCTAssertEqual(exs[0].name, "Squats")
    }

    func test_unmatchedLine_becomesDefaultDraft() async throws {
        let ex = try await parse(["Squats"])[0]
        XCTAssertEqual(ex.name, "Squats")
        XCTAssertEqual(ex.sets, 3)
        XCTAssertEqual(ex.reps, 10)
        XCTAssertEqual(ex.restSec, 30)
        XCTAssertEqual(ex.side, "both")
    }

    func test_listMarkersStripped() async throws {
        let exs = try await parse(["1. Squats 3 x 10", "- Bridges 2 x 8"])
        XCTAssertEqual(exs[0].name, "Squats")
        XCTAssertEqual(exs[1].name, "Bridges")
    }

    // Whole messy handout

    func test_messyHandout() async throws {
        let exs = try await parse([
            "Knee Rehab - Week 3",
            "1. Mini squats 3 x 10, rest 30 sec",
            "2. Straight leg raise x10 each leg",
            "3. Wall sit hold 45 seconds",
            "Page 1 of 1",
        ])
        XCTAssertEqual(exs.count, 4)   // furniture "Page 1 of 1" dropped; title kept as a draft the user deletes
        XCTAssertEqual(exs[1].name, "Mini squats")
        XCTAssertEqual(exs[1].reps, 10)
        XCTAssertEqual(exs[2].reps, 10)
        XCTAssertEqual(exs[2].side, "both")
        XCTAssertEqual(exs[3].durationSec, 45)
    }
}
