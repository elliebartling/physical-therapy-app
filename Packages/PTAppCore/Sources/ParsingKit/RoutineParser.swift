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
        try await parse([image])
    }

    /// Reads every page in order and extracts one routine from all of them.
    public func parse(_ images: [UIImage]) async throws -> ParsedRoutine {
        var pages: [[String]] = []
        for image in images {
            pages.append(try await ocr.recognizeLines(in: image))
        }
        return try await extract(fromPages: pages)
    }

    /// A spoken or typed description of the routine.
    public func parse(transcript: String) async throws -> ParsedRoutine {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ParsingError.noTextFound }
        return try await runChain { try await $0.extract(fromTranscript: text) }
    }

    func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine {
        try await runChain { try await $0.extract(fromOCRLines: lines) }
    }

    /// Pages are kept apart so an extractor with a small input limit can read them in turn.
    func extract(fromPages pages: [[String]]) async throws -> ParsedRoutine {
        let pages = pages.filter { !$0.isEmpty }
        guard !pages.isEmpty else { throw ParsingError.noTextFound }
        return try await runChain { try await $0.extract(fromPages: pages) }
    }

    /// Walks the chain: skips unavailable extractors, falls through on throw.
    private func runChain(
        _ attempt: (any RoutineExtractor) async throws -> ParsedRoutine
    ) async throws -> ParsedRoutine {
        var lastError: Error = ParsingError.allExtractorsFailed
        for extractor in extractors {
            let name = String(describing: type(of: extractor))
            guard extractor.isAvailable else {
                logger.debug("\(name, privacy: .public) skipped: unavailable")
                continue
            }
            do {
                let result = try await attempt(extractor)
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
