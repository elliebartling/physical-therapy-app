import XCTest
import UIKit
import DataKit
@testable import ParsingKit

private struct ThrowingExtractor: RoutineExtractor {
    struct Failure: Error {}
    func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine { throw Failure() }
}

private struct UnavailableExtractor: RoutineExtractor {
    var isAvailable: Bool { false }
    func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine {
        XCTFail("unavailable extractor must never be called")
        return ParsedRoutine(name: "unavailable", exercises: [])
    }
}

final class RoutineParserTests: XCTestCase {
    private let canned = ParsedRoutine(name: "Knee", exercises: [
        .init(name: "Squat", reps: 12, sets: 3, durationSec: nil, restSec: 30, side: "both", notes: "")
    ])

    func test_combinesOCRAndExtractor() async throws {
        let parser = RoutineParser(ocr: OCRService(), extractors: [StubExtractor(result: canned)])
        let url = Bundle.module.url(forResource: "handout_clean", withExtension: "png")!
        let image = UIImage(contentsOfFile: url.path)!
        let parsed = try await parser.parse(image)
        XCTAssertEqual(parsed, canned)
    }

    func test_chain_skipsUnavailableExtractor() async throws {
        let parser = RoutineParser(extractors: [UnavailableExtractor(), StubExtractor(result: canned)])
        let out = try await parser.extract(fromOCRLines: ["anything"])
        XCTAssertEqual(out, canned)
    }

    func test_chain_fallsThroughOnThrow() async throws {
        let parser = RoutineParser(extractors: [ThrowingExtractor(), StubExtractor(result: canned)])
        let out = try await parser.extract(fromOCRLines: ["anything"])
        XCTAssertEqual(out, canned)
    }

    func test_chain_allFail_throwsLastError() async {
        let parser = RoutineParser(extractors: [ThrowingExtractor()])
        do {
            _ = try await parser.extract(fromOCRLines: ["anything"])
            XCTFail("expected throw")
        } catch is ThrowingExtractor.Failure {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_parse_blankImage_throwsNoTextFound() async {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let blank = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        let parser = RoutineParser(extractors: [StubExtractor(result: canned)])
        do {
            _ = try await parser.parse(blank)
            XCTFail("expected throw")
        } catch let e as ParsingError {
            XCTAssertEqual(e, .noTextFound)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
