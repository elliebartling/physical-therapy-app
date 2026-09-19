import Foundation
import UIKit
import os

private let logger = Logger(subsystem: "PTAppCore", category: "parsing")

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
        for extractor in extractors {
            let name = String(describing: type(of: extractor))
            guard extractor.isAvailable else {
                logger.debug("\(name, privacy: .public) skipped: unavailable")
                continue
            }
            do {
                let result = try await extractor.extract(fromOCRLines: lines)
                logger.debug("\(name, privacy: .public) succeeded")
                return result
            } catch {
                logger.error("\(name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                lastError = error
            }
        }
        throw lastError
    }
}
