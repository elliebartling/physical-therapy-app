import Foundation

public protocol RoutineExtractor: Sendable {
    /// Whether this extractor can run right now (e.g. on-device model present).
    /// Defaults to true.
    var isAvailable: Bool { get }
    func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine
    /// Text from a multi-page source, one array of lines per page, in order.
    /// Defaults to reading all the lines at once.
    func extract(fromPages pages: [[String]]) async throws -> ParsedRoutine
    /// A spoken description ("brain dump"). Defaults to splitting it into
    /// sentences and treating them like OCR lines.
    func extract(fromTranscript text: String) async throws -> ParsedRoutine
}

public extension RoutineExtractor {
    var isAvailable: Bool { true }

    func extract(fromTranscript text: String) async throws -> ParsedRoutine {
        try await extract(fromOCRLines: TranscriptSegmenter.lines(from: text))
    }

    func extract(fromPages pages: [[String]]) async throws -> ParsedRoutine {
        try await extract(fromOCRLines: pages.flatMap { $0 })
    }
}

public enum ParsingError: Error, LocalizedError, Equatable {
    case noTextFound
    case allExtractorsFailed
    /// A picked file that isn't a supported type, or can't be opened.
    case unreadableFile

    public var errorDescription: String? {
        switch self {
        case .noTextFound:
            "No readable text was found."
        case .unreadableFile:
            "That file couldn't be opened."
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
