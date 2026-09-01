import Foundation
import UIKit

public struct RoutineParser: Sendable {
    public let ocr: OCRService
    public let extractors: [RoutineExtractor]

    public init(
        ocr: OCRService = .init(),
        extractors: [RoutineExtractor] = [FoundationModelsExtractor(), HeuristicExtractor()]
    ) {
        self.ocr = ocr
        self.extractors = extractors
    }

    public func parse(_ image: UIImage) async throws -> ParsedRoutine {
        let lines = try await ocr.recognizeLines(in: image)
        guard !lines.isEmpty else { throw ParsingError.noTextFound }
        return try await extract(fromOCRLines: lines)
    }

    /// Walks the chain: skips unavailable extractors, falls through on throw.
    func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine {
        var lastError: Error = ParsingError.allExtractorsFailed
        for extractor in extractors where extractor.isAvailable {
            do { return try await extractor.extract(fromOCRLines: lines) }
            catch { lastError = error }
        }
        throw lastError
    }
}
