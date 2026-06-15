import XCTest
import UIKit
@testable import ParsingKit

final class OCRServiceTests: XCTestCase {
    func test_recognizesPrintedText_inFixture() async throws {
        let url = Bundle.module.url(forResource: "handout_clean", withExtension: "png")!
        let image = UIImage(contentsOfFile: url.path)!
        let lines = try await OCRService().recognizeLines(in: image)
        XCTAssertFalse(lines.isEmpty)
        XCTAssertTrue(lines.contains { $0.lowercased().contains("squat") })
    }
}
