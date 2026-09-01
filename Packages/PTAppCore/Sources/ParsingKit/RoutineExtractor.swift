import Foundation

public protocol RoutineExtractor: Sendable {
    /// Whether this extractor can run right now (e.g. on-device model present).
    /// Defaults to true.
    var isAvailable: Bool { get }
    func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine
}

public extension RoutineExtractor {
    var isAvailable: Bool { true }
}

public enum ParsingError: Error, LocalizedError, Equatable {
    case noTextFound
    case allExtractorsFailed

    public var errorDescription: String? {
        switch self {
        case .noTextFound:
            "No readable text was found in the photo."
        case .allExtractorsFailed:
            "Couldn't turn the text into a routine."
        }
    }
}

/// Test double — returns a canned ParsedRoutine.
public struct StubExtractor: RoutineExtractor {
    public let result: ParsedRoutine
    public init(result: ParsedRoutine) { self.result = result }
    public func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine { result }
}
