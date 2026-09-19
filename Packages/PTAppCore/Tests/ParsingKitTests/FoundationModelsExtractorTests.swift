import XCTest
import DataKit
@testable import ParsingKit

final class FoundationModelsExtractorTests: XCTestCase {
    func test_dtoMapping_repsBased() {
        let dto = GenerableExercise(
            name: "Squats", reps: 10, sets: 3, durationSec: nil,
            restSec: 45, side: "left", notes: "slow tempo"
        )
        let ex = dto.toParsedExercise()
        XCTAssertEqual(ex.name, "Squats")
        XCTAssertEqual(ex.reps, 10)
        XCTAssertEqual(ex.sets, 3)
        XCTAssertNil(ex.durationSec)
        XCTAssertEqual(ex.restSec, 45)
        XCTAssertEqual(ex.side, "left")
        XCTAssertEqual(ex.notes, "slow tempo")
    }

    func test_dtoMapping_timeBased_andRoutineName() {
        let dto = GenerableRoutine(name: "Knee rehab", exercises: [
            GenerableExercise(name: "Plank", reps: nil, sets: 2, durationSec: 30,
                              restSec: 30, side: "both", notes: "")
        ])
        let parsed = dto.toParsedRoutine()
        XCTAssertEqual(parsed.name, "Knee rehab")
        XCTAssertEqual(parsed.exercises[0].durationSec, 30)
        XCTAssertNil(parsed.exercises[0].reps)
    }

    func test_dtoMapping_invalidSide_normalizesToBoth() {
        let dto = GenerableExercise(name: "X", reps: 5, sets: 1, durationSec: nil,
                                    restSec: 0, side: "EACH SIDE??", notes: "")
        XCTAssertEqual(dto.toParsedExercise().side, "both")
    }

    func test_isAvailable_returnsWithoutCrashing() {
        _ = FoundationModelsExtractor().isAvailable
    }

    /// Live on-device test. Skips wherever the model is unavailable (CI, most
    /// simulators). Run manually on the Apple Intelligence iPhone.
    ///
    /// Also skips on a model "refusal" — on-device Apple Intelligence applies a
    /// content-safety guardrail to every generation, and it has been observed to
    /// false-positive on this exact benign PT sample (bisection showed each line
    /// individually succeeds, but the combined multi-line prompt is refused with
    /// "May contain sensitive content"). That's an on-device model behavior, not a
    /// defect in this extractor, so it's treated the same as unavailability rather
    /// than failing the suite.
    func test_live_extractsFromSampleLines() async throws {
        let extractor = FoundationModelsExtractor()
        guard extractor.isAvailable else {
            throw XCTSkip("Foundation Models unavailable on this destination")
        }
        let parsed: ParsedRoutine
        do {
            parsed = try await extractor.extract(fromOCRLines: [
                "Knee Rehab Program",
                "1. Mini squats 3 x 10, rest 45 sec",
                "2. Plank: hold 30 seconds, 3 sets",
                "3. Straight leg raise x10 each leg",
            ])
        } catch {
            let description = String(describing: error)
            if description.contains("refusal") || description.contains("sensitive content") {
                throw XCTSkip("On-device model declined this sample content (safety-guardrail false positive): \(description)")
            }
            throw error
        }
        XCTAssertGreaterThanOrEqual(parsed.exercises.count, 3)
        XCTAssertTrue(parsed.exercises.contains { $0.durationSec != nil })
    }
}
