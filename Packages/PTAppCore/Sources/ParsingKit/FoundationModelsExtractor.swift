import Foundation
import FoundationModels
import DataKit

/// On-device LLM extractor. One of two files in the package allowed to
/// import FoundationModels (the other is MediaKit/FoundationModelsRanker.swift).
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
    Where the handout prints labelled instruction text for an exercise, copy each block into \
    sheetHowTo with its heading verbatim, in printed order; leave sheetHowTo empty otherwise. \
    Never write instructions of your own, and keep that text out of notes.
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
    @Guide(description: "The handout's own labelled instruction blocks for this exercise (for example Setup, Movement, Tip, or whatever headings the sheet uses), in the order printed, each with its heading copied verbatim and its text copied from the sheet. Empty when the sheet has no instruction text for this exercise. Never write or paraphrase instructions that are not on the sheet.")
    var sheetHowTo: [GenerableHowToSection]

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
            notes: notes,
            sheetHowTo: sheetHowTo.compactMap { $0.toHowToSection() }
        )
    }
}

@Generable
struct GenerableHowToSection {
    @Guide(description: "The block's heading exactly as printed on the sheet")
    var heading: String
    @Guide(description: "The block's text as printed on the sheet")
    var body: String

    func toHowToSection() -> HowToSection? {
        let heading = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        return HowToSection(heading: heading, body: body)
    }
}
