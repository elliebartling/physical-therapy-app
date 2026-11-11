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

/// Records what the parser hands it, so tests can check page order and routing.
private final class RecordingExtractor: RoutineExtractor, @unchecked Sendable {
    let result: ParsedRoutine
    private(set) var ocrLines: [String]?
    private(set) var transcript: String?

    init(result: ParsedRoutine) { self.result = result }

    func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine {
        ocrLines = lines
        return result
    }

    func extract(fromTranscript text: String) async throws -> ParsedRoutine {
        transcript = text
        return result
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

    func test_parseMultipleImages_readsEveryPageInOrderIntoOneExtraction() async throws {
        let url = Bundle.module.url(forResource: "handout_clean", withExtension: "png")!
        let page = UIImage(contentsOfFile: url.path)!
        let onePage = try await OCRService().recognizeLines(in: page)
        XCTAssertFalse(onePage.isEmpty)

        let recorder = RecordingExtractor(result: canned)
        let parser = RoutineParser(ocr: OCRService(), extractors: [recorder])
        let parsed = try await parser.parse([page, page])

        XCTAssertEqual(parsed, canned)
        XCTAssertEqual(recorder.ocrLines, onePage + onePage)
    }

    func test_parseMultipleImages_allBlank_throwsNoTextFound() async {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let blank = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        let parser = RoutineParser(extractors: [StubExtractor(result: canned)])
        do {
            _ = try await parser.parse([blank, blank])
            XCTFail("expected throw")
        } catch let e as ParsingError {
            XCTAssertEqual(e, .noTextFound)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_parseTranscript_routesTrimmedTextToTranscriptExtraction() async throws {
        let recorder = RecordingExtractor(result: canned)
        let parser = RoutineParser(extractors: [recorder])
        let parsed = try await parser.parse(transcript: "  Clamshells, three sets of twelve.  \n")

        XCTAssertEqual(parsed, canned)
        XCTAssertEqual(recorder.transcript, "Clamshells, three sets of twelve.")
        XCTAssertNil(recorder.ocrLines)
    }

    func test_parseTranscript_blank_throwsNoTextFound() async {
        let parser = RoutineParser(extractors: [StubExtractor(result: canned)])
        do {
            _ = try await parser.parse(transcript: "   \n ")
            XCTFail("expected throw")
        } catch let e as ParsingError {
            XCTAssertEqual(e, .noTextFound)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_parseTranscript_fallsThroughChainLikeOCR() async throws {
        let parser = RoutineParser(extractors: [ThrowingExtractor(), StubExtractor(result: canned)])
        let out = try await parser.parse(transcript: "Bridges, two sets of ten")
        XCTAssertEqual(out, canned)
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
