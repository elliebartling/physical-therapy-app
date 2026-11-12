import Foundation
import FoundationModels

/// On-device LLM extractor. The only file in the package allowed to
/// import FoundationModels.
public struct FoundationModelsExtractor: RoutineExtractor {
    public init() {}

    public var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine {
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: lines.joined(separator: "\n"),
            generating: GenerableRoutine.self
        )
        return response.content.toParsedRoutine()
    }

    /// The on-device model's context window (about 4k tokens) has to hold the instructions,
    /// the input and every exercise it writes back, so a multi-page handout is read a chunk
    /// at a time and the exercises joined in order.
    public func extract(fromPages pages: [[String]]) async throws -> ParsedRoutine {
        var name: String?
        var exercises: [ParsedRoutine.ParsedExercise] = []
        for chunk in PageChunker.chunks(pages, maxCharacters: Self.maxChunkCharacters) {
            let part = try await extractFitting(chunk)
            if name == nil, !part.exercises.isEmpty { name = part.name }
            exercises += part.exercises
        }
        return ParsedRoutine(name: name ?? "My routine", exercises: exercises)
    }

    /// About 1,000–1,500 tokens of handout text, leaving room for a page's worth of exercises.
    static let maxChunkCharacters = 4_000

    /// Reads `lines`, halving them and trying again if they still overflow the window.
    private func extractFitting(_ lines: [String]) async throws -> ParsedRoutine {
        do {
            return try await extract(fromOCRLines: lines)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize where lines.count > 1 {
            let middle = lines.count / 2
            let first = try await extractFitting(Array(lines[..<middle]))
            let second = try await extractFitting(Array(lines[middle...]))
            return ParsedRoutine(name: first.exercises.isEmpty ? second.name : first.name,
                                 exercises: first.exercises + second.exercises)
        }
    }

    public func extract(fromTranscript text: String) async throws -> ParsedRoutine {
        let session = LanguageModelSession(instructions: Self.transcriptInstructions)
        let response = try await session.respond(to: text, generating: GenerableRoutine.self)
        return response.content.toParsedRoutine()
    }

    static let transcriptInstructions = """
    You will be given someone's spoken description of their physical therapy routine, \
    transcribed by speech recognition. It may be informal, out of order, and include filler \
    words or corrections such as "actually, make that fifteen". When the speaker corrects \
    themselves, use the correction. Write spoken numbers as digits ("twelve" → 12, \
    "half a minute" → 30 seconds).
    Extract a structured routine. For each exercise capture: name, reps OR durationSec, \
    sets, restSec, side (one of: both, left, right, alternating), and notes.
    Default sets to 3, reps to 10, restSec to 30, and side to "both" if not stated. \
    "Each side" or "each leg" means side "both".
    """

    static let instructions = """
    You will be given OCR lines from a physical therapy exercise handout.
    Extract a structured routine. For each exercise capture: name, reps OR durationSec, \
    sets, restSec, side (one of: both, left, right, alternating), and notes.
    Default sets to 3, reps to 10, restSec to 30, and side to "both" if not stated. \
    Ignore page furniture such as dates, clinic names, page numbers, and contact details.
    """
}

@Generable
struct GenerableRoutine {
    @Guide(description: "Short name for the routine, e.g. 'Knee rehab'")
    var name: String
    var exercises: [GenerableExercise]

    func toParsedRoutine() -> ParsedRoutine {
        ParsedRoutine(name: name, exercises: exercises.map { $0.toParsedExercise() })
    }
}

@Generable
struct GenerableExercise {
    @Guide(description: "Exercise name")
    var name: String
    @Guide(description: "Repetitions per set; 10 when not stated and the exercise is rep-based; omit when the exercise is time-based")
    var reps: Int?
    @Guide(description: "Number of sets; 3 when not stated")
    var sets: Int
    @Guide(description: "Hold duration in seconds; omit when rep-based")
    var durationSec: Int?
    @Guide(description: "Rest in seconds between sets; 30 when not stated")
    var restSec: Int
    @Guide(description: "Exactly one of: both, left, right, alternating")
    var side: String
    @Guide(description: "Extra instructions; empty string when none")
    var notes: String

    func toParsedExercise() -> ParsedRoutine.ParsedExercise {
        let validSides = ["both", "left", "right", "alternating"]
        let normalizedSide = side.lowercased().trimmingCharacters(in: .whitespaces)
        return .init(
            name: name,
            reps: reps.map { max(0, $0) },
            sets: max(1, sets),
            durationSec: durationSec.map { max(0, $0) },
            restSec: max(0, restSec),
            side: validSides.contains(normalizedSide) ? normalizedSide : "both",
            notes: notes
        )
    }
}
