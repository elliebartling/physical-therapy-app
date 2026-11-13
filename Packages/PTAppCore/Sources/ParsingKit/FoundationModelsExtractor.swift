import Foundation
import FoundationModels
import DataKit
import os

private let logger = Logger(subsystem: "PTAppCore", category: "parsing")

/// On-device LLM extractor. One of two files in the package allowed to
/// import FoundationModels (the other is MediaKit/FoundationModelsRanker.swift).
public struct FoundationModelsExtractor: RoutineExtractor {
    public init() {}

    public var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine {
        let source = lines.joined(separator: "\n")
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: source,
            generating: GenerableRoutine.self
        )
        return response.content.toParsedRoutine(source: source)
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
        return response.content.toParsedRoutine(source: text)
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

    func toParsedRoutine(source: String) -> ParsedRoutine {
        ParsedRoutine(name: name, exercises: exercises.map { $0.toParsedExercise(source: source) })
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
    @Guide(description: "Incidental remarks that are NOT part of a labelled instruction block (those belong in sheetHowTo); empty string when none")
    var notes: String
    @Guide(description: "The handout's own labelled instruction blocks for this exercise (for example Setup, Movement, Tip, or whatever headings the sheet uses), in the order printed, each with its heading copied verbatim and its text copied from the sheet. Empty when the sheet has no instruction text for this exercise. Never write or paraphrase instructions that are not on the sheet.")
    var sheetHowTo: [GenerableHowToSection]

    func toParsedExercise(source: String) -> ParsedRoutine.ParsedExercise {
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
            sheetHowTo: sheetHowTo.compactMap { section in
                let kept = section.toHowToSection(source: source)
                if kept == nil {
                    logger.debug("Dropped a how-to section for \(name): body empty or not found in the source text")
                }
                return kept
            }
        )
    }
}

@Generable
struct GenerableHowToSection {
    @Guide(description: "The block's heading exactly as printed on the sheet")
    var heading: String
    @Guide(description: "The block's text as printed on the sheet")
    var body: String

    /// Keeps the block only if its text really appears in `source`. The model is asked to copy,
    /// but a paraphrase is the phone writing rehab guidance, so this is enforced here, not by
    /// the prompt. A heading that is not on the sheet is blanked rather than shown.
    func toHowToSection(source: String) -> HowToSection? {
        let heading = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let haystack = SheetText.normalised(source)
        let needle = SheetText.normalised(body)
        guard !needle.isEmpty, haystack.contains(needle) else { return nil }
        let headingIsOnSheet = haystack.contains(SheetText.normalised(heading))
        return HowToSection(heading: headingIsOnSheet ? heading : "", body: body)
    }
}

/// Comparison form for "is this text on the sheet": OCR, PDF text and the model disagree on
/// case, whitespace runs, and smart versus straight punctuation, none of which change meaning.
enum SheetText {
    static func normalised(_ text: String) -> String {
        // NFKC folds PDF ligatures (ﬁ, ﬂ) to plain letters; soft hyphens are invisible.
        let unified = text.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "\u{00AD}", with: "")
        // A hyphen that only marks a line break ("stand-\ning") joins the word back up.
        let joined = unified.replacingOccurrences(
            of: "[-\u{2010}\u{2011}][ \\t]*\\r?\\n[ \\t]*", with: "", options: .regularExpression)
        let folded = joined
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .lowercased()
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
