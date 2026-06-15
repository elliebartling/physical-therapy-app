import XCTest
import DataKit
@testable import ParsingKit

final class FoundationModelsParserTests: XCTestCase {
    func test_stubExtractor_returnsConfiguredRoutine() async throws {
        let canned = ParsedRoutine(name: "Test", exercises: [
            .init(name: "X", reps: 5, sets: 1, durationSec: nil, restSec: 0, side: "both", notes: "")
        ])
        let extractor: RoutineExtractor = StubExtractor(result: canned)
        let out = try await extractor.extract(fromOCRLines: ["irrelevant"])
        XCTAssertEqual(out, canned)
    }

    func test_foundationModelsParser_throwsUntilWired() async {
        do {
            _ = try await FoundationModelsParser().extract(fromOCRLines: ["squat 3x10"])
            XCTFail("expected throw")
        } catch {
            // expected
        }
    }
}
