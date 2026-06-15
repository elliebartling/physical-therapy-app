import Foundation
import DataKit

public protocol RoutineExtractor: Sendable {
    func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine
}

public struct FoundationModelsParser: RoutineExtractor {
    public init() {}

    public func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine {
        // TODO(verify-with-docs): Use the current Foundation Models LanguageModelSession
        // API to produce a structured ParsedRoutine from the OCR lines. Pseudocode:
        //
        //   let session = LanguageModelSession()
        //   let response = try await session.respond(
        //       to: instruction(for: lines),
        //       generating: ParsedRoutine.self
        //   )
        //   return response.content
        //
        // If structured output requires conforming ParsedRoutine to a macro (e.g. @Generable),
        // add it to ParsedRoutine and ParsedExercise after verifying the macro exists in
        // the current SDK. Until then, this is unimplemented — callers should inject a
        // StubExtractor or a future cloud-LLM-backed extractor.
        throw NSError(
            domain: "FoundationModelsParser",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Foundation Models wiring deferred — verify API and implement."]
        )
    }

    func instruction(for lines: [String]) -> String {
        """
        You will be given OCR lines from a physical therapy exercise handout.
        Extract a structured routine. For each exercise capture: name, reps OR durationSec,
        sets, restSec, side (one of: both, left, right, alternating), and notes.
        Default restSec to 30 and side to "both" if not stated.

        OCR LINES:
        \(lines.joined(separator: "\n"))
        """
    }
}

/// Test double — returns a canned ParsedRoutine.
public struct StubExtractor: RoutineExtractor {
    public let result: ParsedRoutine
    public init(result: ParsedRoutine) { self.result = result }
    public func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine { result }
}
