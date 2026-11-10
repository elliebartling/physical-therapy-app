import XCTest
@testable import DataKit

final class ExerciseTargetTests: XCTestCase {
    func test_repsSets_roundTripsThroughCodable() throws {
        let original = ExerciseTarget.repsSets(reps: 12, sets: 3)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExerciseTarget.self, from: data)
        XCTAssertEqual(original, decoded)
    }
    func test_timeSets_roundTripsThroughCodable() throws {
        let original = ExerciseTarget.timeSets(seconds: 30, sets: 4)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExerciseTarget.self, from: data)
        XCTAssertEqual(original, decoded)
    }
    func test_totalSets_returnsSetsForBothCases() {
        XCTAssertEqual(ExerciseTarget.repsSets(reps: 12, sets: 3).totalSets, 3)
        XCTAssertEqual(ExerciseTarget.timeSets(seconds: 30, sets: 4).totalSets, 4)
    }
}
