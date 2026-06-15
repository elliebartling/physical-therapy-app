import XCTest
import UIKit
import DataKit
@testable import ParsingKit

final class RoutineParserTests: XCTestCase {
    func test_combinesOCRAndExtractor() async throws {
        let canned = ParsedRoutine(name: "Knee", exercises: [
            .init(name: "Squat", reps: 12, sets: 3, durationSec: nil, restSec: 30, side: "both", notes: "")
        ])
        let parser = RoutineParser(ocr: OCRService(), extractor: StubExtractor(result: canned))
        let url = Bundle.module.url(forResource: "handout_clean", withExtension: "png")!
        let image = UIImage(contentsOfFile: url.path)!
        let parsed = try await parser.parse(image)
        XCTAssertEqual(parsed, canned)
    }
}
