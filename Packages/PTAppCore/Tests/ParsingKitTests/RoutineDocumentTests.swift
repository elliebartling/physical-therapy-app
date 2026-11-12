import XCTest
import UIKit
@testable import ParsingKit

/// Records the lines the parser hands over, so tests can check what was read.
private final class LineRecorder: RoutineExtractor, @unchecked Sendable {
    private(set) var lines: [String] = []
    func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine {
        self.lines = lines
        return ParsedRoutine(name: "Recorded", exercises: [])
    }
}

final class RoutineDocumentTests: XCTestCase {
    private var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
    }

    private func read(_ documents: [RoutineDocument]) async throws -> [String] {
        let recorder = LineRecorder()
        _ = try await RoutineParser(extractors: [recorder]).parse(documents: documents)
        return recorder.lines
    }

    /// A one-page PDF with a real text layer.
    private func textPDF(_ lines: [String]) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            (lines.joined(separator: "\n") as NSString).draw(
                in: CGRect(x: 72, y: 72, width: 468, height: 648),
                withAttributes: [.font: UIFont.systemFont(ofSize: 18)]
            )
        }
    }

    /// A one-page PDF that's only a picture of the handout, like a scan.
    private func scannedPDF() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "handout_clean", withExtension: "png"))
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path))
        let bounds = CGRect(origin: .zero, size: image.size)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            image.draw(in: bounds)
        }
    }

    // MARK: Reading

    func test_text_dropsBlankLinesAndTrims() async throws {
        let lines = try await read([.text("  Bridges 3x10 \n\n Clams 2x15\n")])
        XCTAssertEqual(lines, ["Bridges 3x10", "Clams 2x15"])
    }

    func test_pdfWithText_readsItsText() async throws {
        let lines = try await read([.pdf(textPDF(["Bridges 3 x 10", "Clamshells 2 x 15"]))])
        let joined = lines.joined(separator: " ")
        let bridges = try XCTUnwrap(joined.range(of: "Bridges"))
        let clams = try XCTUnwrap(joined.range(of: "Clamshells"))
        XCTAssertLessThan(bridges.lowerBound, clams.lowerBound)
    }

    func test_scannedPDF_isReadLikeAPhoto() async throws {
        let lines = try await read([.pdf(scannedPDF())])
        XCTAssertFalse(lines.isEmpty, "a PDF with no text layer should be OCR'd")
    }

    func test_severalDocuments_areReadInOrderAsOneRoutine() async throws {
        let lines = try await read([.text("Warm-up walk 5 min"), .pdf(textPDF(["Bridges 3 x 10"]))])
        XCTAssertEqual(lines.first, "Warm-up walk 5 min")
        XCTAssertTrue(lines.dropFirst().joined(separator: " ").contains("Bridges"))
    }

    func test_emptyText_isNoTextFound() async {
        do {
            _ = try await read([.text(" \n ")])
            XCTFail("expected noTextFound")
        } catch {
            XCTAssertEqual(error as? ParsingError, .noTextFound)
        }
    }

    func test_brokenFiles_areUnreadable() async {
        for document in [RoutineDocument.pdf(Data("not a pdf".utf8)), .image(Data([1, 2, 3]))] {
            do {
                _ = try await read([document])
                XCTFail("expected unreadableFile for \(document)")
            } catch {
                XCTAssertEqual(error as? ParsingError, .unreadableFile)
            }
        }
    }

    // MARK: Files

    func test_files_areReadByType() throws {
        let txt = temp.appendingPathComponent("routine.txt")
        try "Bridges 3x10".write(to: txt, atomically: true, encoding: .utf8)
        XCTAssertEqual(try RoutineDocument(contentsOf: txt), .text("Bridges 3x10"))

        let pdfData = textPDF(["Bridges"])
        let pdf = temp.appendingPathComponent("routine.pdf")
        try pdfData.write(to: pdf)
        XCTAssertEqual(try RoutineDocument(contentsOf: pdf), .pdf(pdfData))

        let rtf = temp.appendingPathComponent("routine.rtf")
        let attributed = NSAttributedString(string: "Clams 2x15")
        try attributed.data(from: NSRange(location: 0, length: attributed.length),
                            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            .write(to: rtf)
        guard case .text(let text) = try RoutineDocument(contentsOf: rtf) else {
            return XCTFail("RTF should be read as text")
        }
        XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), "Clams 2x15")
    }

    func test_unsupportedOrMissingFiles_areUnreadable() throws {
        let zip = temp.appendingPathComponent("routine.zip")
        try Data([0x50, 0x4B]).write(to: zip)
        XCTAssertThrowsError(try RoutineDocument(contentsOf: zip)) {
            XCTAssertEqual($0 as? ParsingError, .unreadableFile)
        }
        XCTAssertThrowsError(try RoutineDocument(contentsOf: temp.appendingPathComponent("missing.txt"))) {
            XCTAssertEqual($0 as? ParsingError, .unreadableFile)
        }
    }

    func test_parseFileURLs_readsEachFileInOrder() async throws {
        let first = temp.appendingPathComponent("page1.txt")
        let second = temp.appendingPathComponent("page2.txt")
        try "Bridges 3x10".write(to: first, atomically: true, encoding: .utf8)
        try "Clams 2x15".write(to: second, atomically: true, encoding: .utf8)
        let recorder = LineRecorder()

        _ = try await RoutineParser(extractors: [recorder]).parse(fileURLs: [first, second])

        XCTAssertEqual(recorder.lines, ["Bridges 3x10", "Clams 2x15"])
    }
}
