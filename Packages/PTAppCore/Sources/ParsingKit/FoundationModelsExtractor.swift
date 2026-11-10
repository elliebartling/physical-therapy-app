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
