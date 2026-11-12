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
            generating: GenerableRanking.self,
            options: GenerationOptions(temperature: 0)
        )
        return try Self.slugs(from: response.content, candidates: candidates)
    }

    /// Maps the model's 1-based numbers back to slugs. "No match" is `[]`.
    /// A "same" verdict with no usable number is a failed answer, not a
    /// "none", so it throws and the matcher falls back to stage 1.
    static func slugs(from ranking: GenerableRanking, candidates: [ScoredCandidate]) throws -> [String] {
        guard ranking.verdict == .same else { return [] }
        let slugs = ranking.choices
            .filter { candidates.indices.contains($0 - 1) }
            .map { candidates[$0 - 1].entry.slug }
        guard !slugs.isEmpty else { throw RankerFailure() }
        return slugs
    }

    static let maxNotesLength = 200

    static let instructions = """
    You match an exercise from a physical therapy handout to pictures in a small \
    illustration library. You will get the handout exercise and a numbered list of \
    library entries, each as: number | name | equipment.

    The library is small and does NOT contain most exercises. "none" is a normal, \
    frequent, correct answer. A wrong picture is worse than no picture, because the \
    person will do the exercise while looking at it.

    Say "same" when at least one entry shows the same movement as the handout. It is \
    still the same movement when it differs only in wording (a clinical name versus a \
    common name, such as "heel slides" and "knee flexion on your back"), or in support, \
    prop, equipment, side, or starting position: a wall, a towel, a band, a chair, \
    kneeling instead of standing, left instead of right.

    Say "none" when no entry matches on joint action, direction of movement, and muscle \
    being worked. Sharing a word such as "raise", "bridge" or "squat" is not enough, and \
    a stretch is not a strengthening exercise. When unsure between a poor match and \
    "none", say "none".

    Answer with the entry numbers only, copied exactly from the list.
    """

    static func prompt(name: String, notes: String, candidates: [ScoredCandidate]) -> String {
        let list = candidates.enumerated().map { offset, c in
            "\(offset + 1) | \(c.entry.name) | \(c.entry.equipment)"
        }.joined(separator: "\n")
        let trimmedNotes = String(
            notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNotesLength)
        )
        return """
        Handout exercise: \(name)
        Handout notes: \(trimmedNotes.isEmpty ? "(none)" : trimmedNotes)

        Library entries:
        \(list)
        """
    }
}

@Generable
enum GenerableVerdict: String {
    case same
    case none
}

@Generable
struct GenerableRanking {
    @Guide(description: "One short sentence: the movement the handout describes, and whether a library entry shows that same movement or only a related one.")
    var reasoning: String
    @Guide(description: "same if an entry shows the same movement; none if not. none is common and correct.")
    var verdict: GenerableVerdict
    @Guide(description: "Up to 4 entry numbers from the list, best first. Empty when the verdict is none.", .maximumCount(4))
    var choices: [Int]
}
