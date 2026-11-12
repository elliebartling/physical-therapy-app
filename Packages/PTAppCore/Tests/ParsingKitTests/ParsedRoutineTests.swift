import XCTest
import DataKit
@testable import ParsingKit

final class ParsedRoutineTests: XCTestCase {
    func test_toRoutine_mapsExercisesInOrder() {
        let parsed = ParsedRoutine(name: "Knee", exercises: [
            .init(name: "Squat", reps: 12, sets: 3, durationSec: nil, restSec: 30, side: "both", notes: ""),
            .init(name: "Plank", reps: nil, sets: 2, durationSec: 30, restSec: 20, side: "both", notes: ""),
        ])
        let routine = parsed.toRoutine()
        XCTAssertEqual(routine.exercises.count, 2)
        let ordered = routine.exercises.sorted { $0.order < $1.order }
        XCTAssertEqual(ordered[0].target, .repsSets(reps: 12, sets: 3))
        XCTAssertEqual(ordered[1].target, .timeSets(seconds: 30, sets: 2))
        XCTAssertEqual(ordered[0].side, .both)
    }

    func test_toRoutineCarriesArtChoice() {
        let parsed = ParsedRoutine(name: "R", exercises: [
            .init(name: "Bird Dog", reps: 10, sets: 3, durationSec: nil, restSec: 30,
                  side: "both", notes: "", art: .library(slug: "bird-dog")),
            .init(name: "Mystery", reps: 10, sets: 3, durationSec: nil, restSec: 30,
                  side: "both", notes: "", art: .none),
        ])
        XCTAssertEqual(parsed.toRoutine().orderedExercises.map(\.art),
                       [.library(slug: "bird-dog"), .none])
    }

    func test_decodingWithoutArtDefaultsToUnmatched() throws {
        let json = #"{"name":"R","exercises":[{"name":"X","sets":3,"restSec":30,"side":"both","notes":""}]}"#
        let parsed = try JSONDecoder().decode(ParsedRoutine.self, from: Data(json.utf8))
        XCTAssertEqual(parsed.exercises[0].art, .unmatched)
    }
}
