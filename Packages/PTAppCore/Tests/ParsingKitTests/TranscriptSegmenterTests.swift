import XCTest
@testable import ParsingKit

final class TranscriptSegmenterTests: XCTestCase {
    func test_splitsOnSentenceEndsAndNewlines() {
        let text = "Clamshells, three sets of twelve each side. Then side plank 30 seconds!\nBridges; heel raises"
        XCTAssertEqual(TranscriptSegmenter.lines(from: text), [
            "Clamshells, three sets of twelve each side",
            "Then side plank 30 seconds",
            "Bridges",
            "heel raises",
        ])
    }

    func test_dropsEmptyFragments() {
        XCTAssertEqual(TranscriptSegmenter.lines(from: " ... \n\n"), [])
    }

    func test_defaultTranscriptExtraction_feedsSentencesAsLines() async throws {
        // HeuristicExtractor doesn't override extract(fromTranscript:), so it gets sentences as lines.
        let parsed = try await HeuristicExtractor().extract(fromTranscript: "Bridges 3 x 10. Wall sit hold 30 sec")
        XCTAssertEqual(parsed.exercises.map(\.name), ["Bridges", "Wall sit"])
        XCTAssertEqual(parsed.exercises.first?.reps, 10)
        XCTAssertEqual(parsed.exercises.last?.durationSec, 30)
    }
}
