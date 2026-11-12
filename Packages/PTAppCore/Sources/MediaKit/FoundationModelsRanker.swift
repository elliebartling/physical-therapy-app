import Foundation
import FoundationModels

/// On-device LLM ranker. With `FoundationModelsExtractor`, one of the only two
/// files in the package allowed to import FoundationModels.
public struct FoundationModelsRanker: CandidateRanker {
    public init() {}

    public var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func rank(name: String, notes: String, candidates: [ScoredCandidate]) async throws -> [String] {
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: Self.prompt(name: name, notes: notes, candidates: candidates),
            generating: GenerableRanking.self
        )
        let ranking = response.content
        // The model must commit to a verdict first; "none" overrides any slugs.
        guard ranking.verdict == Verdict.sameMovement.rawValue else { return [] }
        return ranking.slugs
    }

    enum Verdict: String {
        case sameMovement = "same"
        case noneOfThese = "none"
    }

    static let instructions = """
    You match an exercise from a physical therapy handout to pictures in a small \
    illustration library. You will get the handout exercise and a numbered list of \
    library entries, each as: slug | name | equipment | main muscle | stretch or exercise.

    The library is small and does NOT contain most exercises. "none" is a normal, \
    frequent, correct answer. A wrong picture is worse than no picture, because the \
    person will do the exercise while looking at it.

    Say "same" only when at least one entry shows the same movement as the handout, \
    allowing for different wording, a clinical name versus a common name \
    (for example "quadruped opposite arm/leg raise" is "bird dog"), a different side, \
    or a different starting position that is otherwise the same movement.

    Say "none" when the best entry is only related: the same body part but a different \
    movement, a stretch where the handout asks for a strengthening exercise (or the \
    reverse), a different position or direction, or equipment the handout does not use. \
    Sharing a word such as "raise", "bridge" or "squat" is not enough. When unsure \
    between a poor match and "none", say "none".

    Only use slugs copied exactly from the list. Never invent a slug.
    """

    static func prompt(name: String, notes: String, candidates: [ScoredCandidate]) -> String {
        let list = candidates.map { c -> String in
            let e = c.entry
            return "\(e.slug) | \(e.name) | \(e.equipment) | \(e.primaryMuscle) | \(e.isStretch ? "stretch" : "exercise")"
        }.joined(separator: "\n")
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Handout exercise: \(name)
        Handout notes: \(trimmedNotes.isEmpty ? "(none)" : trimmedNotes)

        Library entries:
        \(list)
        """
    }
}

@Generable
struct GenerableRanking {
    @Guide(description: "One short sentence: the movement the handout describes, and whether a library entry shows that same movement or only a related one.")
    var reasoning: String
    @Guide(description: "Exactly one of: same, none. Use none when no entry shows the same movement. none is common and correct.")
    var verdict: String
    @Guide(description: "Up to 3 slugs copied exactly from the list, best first. Empty when the verdict is none.", .maximumCount(3))
    var slugs: [String]
}
