import XCTest
import DataKit
@testable import ParsingKit

final class FoundationModelsExtractorTests: XCTestCase {
    func test_dtoMapping_repsBased() {
        let dto = GenerableExercise(
            name: "Squats", reps: 10, sets: 3, durationSec: nil,
            restSec: 45, side: "left", notes: "slow tempo", sheetHowTo: []
        )
        let ex = dto.toParsedExercise(source: "")
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
                              restSec: 30, side: "both", notes: "", sheetHowTo: [])
        ])
        let parsed = dto.toParsedRoutine(source: "")
        XCTAssertEqual(parsed.name, "Knee rehab")
        XCTAssertEqual(parsed.exercises[0].durationSec, 30)
        XCTAssertNil(parsed.exercises[0].reps)
    }

    func test_dtoMapping_invalidSide_normalizesToBoth() {
        let dto = GenerableExercise(name: "X", reps: 5, sets: 1, durationSec: nil,
                                    restSec: 0, side: "EACH SIDE??", notes: "", sheetHowTo: [])
        XCTAssertEqual(dto.toParsedExercise(source: "").side, "both")
    }

    private static let sheet = """
    Slant board stretch
    Setup \u{2014} Begin by standing behind a slant board.
    Tip \u{2014} You can hold onto a wall or pole for balance as needed.  Keep your
    heels down on the slant board.
    """

    private func exercise(_ sections: [GenerableHowToSection]) -> GenerableExercise {
        GenerableExercise(name: "X", reps: 5, sets: 1, durationSec: nil, restSec: 0,
                          side: "both", notes: "", sheetHowTo: sections)
    }

    func test_sections_presentOnTheSheet_areKeptVerbatimInOrder() {
        let ex = exercise([
            GenerableHowToSection(heading: "Setup", body: "Begin by standing behind a slant board."),
            GenerableHowToSection(heading: "Tip", body: "You can hold onto a wall or pole for balance as needed."),
        ]).toParsedExercise(source: Self.sheet)
        XCTAssertEqual(ex.sheetHowTo.map(\.heading), ["Setup", "Tip"])
        XCTAssertEqual(ex.sheetHowTo.first?.body, "Begin by standing behind a slant board.")
        XCTAssertEqual(ex.notes, "", "sheet prose must not reach notes")
    }

    func test_sections_matchAcrossCaseWhitespaceAndSmartQuotes() {
        let source = "Tip \u{2014} Don\u{2019}t let your knee\ncollapse inward."
        let ex = exercise([
            GenerableHowToSection(heading: "tip", body: "DON'T let your knee collapse   inward."),
        ]).toParsedExercise(source: source)
        XCTAssertEqual(ex.sheetHowTo.count, 1)
    }

    func test_sections_nearParaphrase_isDropped() {
        let ex = exercise([
            GenerableHowToSection(heading: "Setup", body: "Start by standing in front of a slant board."),
        ]).toParsedExercise(source: Self.sheet)
        XCTAssertEqual(ex.sheetHowTo, [])
    }

    func test_sections_whollyInvented_isDropped() {
        let ex = exercise([
            GenerableHowToSection(heading: "Movement", body: "Keep your back straight and breathe out."),
            GenerableHowToSection(heading: "Tip", body: "Keep your heels down on the slant board."),
        ]).toParsedExercise(source: Self.sheet)
        XCTAssertEqual(ex.sheetHowTo.map(\.heading), ["Tip"])
    }

    func test_sections_headingNotOnTheSheet_isBlankedButVerbatimBodyKept() {
        let ex = exercise([
            GenerableHowToSection(heading: "Important safety", body: "Begin by standing behind a slant board."),
        ]).toParsedExercise(source: Self.sheet)
        XCTAssertEqual(ex.sheetHowTo.map(\.heading), [""])
        XCTAssertEqual(ex.sheetHowTo.map(\.body), ["Begin by standing behind a slant board."])
    }

    func test_sections_emptyBody_isDropped() {
        let ex = exercise([
            GenerableHowToSection(heading: "Tip", body: "  "),
        ]).toParsedExercise(source: Self.sheet)
        XCTAssertEqual(ex.sheetHowTo, [])
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
    ///
    /// Likewise skips when the model reports itself available but its assets are
    /// missing at generation time (ModelManagerError / UnifiedAssetFramework), as
    /// seen on macOS CI runners: the model can't run there either.
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
            if description.contains("ModelManagerError") || description.contains("UnifiedAssetFramework") {
                throw XCTSkip("On-device model assets are missing on this destination: \(description)")
            }
            throw error
        }
        XCTAssertGreaterThanOrEqual(parsed.exercises.count, 3)
        XCTAssertTrue(parsed.exercises.contains { $0.durationSec != nil })
    }
}
