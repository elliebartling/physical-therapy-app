import DataKit
import Foundation
import os

private let logger = Logger(subsystem: "PTAppCore", category: "media")

/// Stage 2 of matching: picks the library entries that show the same movement
/// as a handout exercise, or says that none of them do.
public protocol CandidateRanker: Sendable {
    var isAvailable: Bool { get }
    /// Slugs from `candidates`, best first. Empty means "none of these".
    func rank(name: String, notes: String, candidates: [ScoredCandidate]) async throws -> [String]
}

/// The outcome of matching one exercise.
public struct MatchResult: Sendable, Equatable {
    public let choice: ArtChoice
    /// Other plausible slugs, best first, for the user to switch to.
    public let alternatives: [String]

    public init(choice: ArtChoice, alternatives: [String]) {
        self.choice = choice
        self.alternatives = alternatives
    }
}

/// Decides which library illustration (if any) an exercise gets.
///
/// Stage 1 is the local lexical `CandidateScorer`. Stage 2 is an on-device
/// model that ranks candidates and may decline them all. When the model is
/// unavailable, or throws, stage 1 stands alone behind `floor`.
///
/// A high stage-1 score never bypasses the model: 0.6-0.7 only means "same
/// word family" ("Wall Squat" vs "Squat"), and telling those apart is the
/// model's job. When the shortlist is empty or weak (top score below
/// `wideningThreshold`) the model is given the whole catalogue, because
/// lexical scoring cannot bridge clinical names to common ones.
public struct ExerciseMatcher: Sendable {
    /// How many alternatives to offer next to the chosen picture.
    static let maxAlternatives = 3

    private let scorer: CandidateScorer
    private let catalog: ExerciseCatalog
    private let ranker: any CandidateRanker
    private let floor: Double
    private let wideningThreshold: Double

    public init(
        scorer: CandidateScorer = .init(),
        catalog: ExerciseCatalog = .bundled,
        ranker: any CandidateRanker = FoundationModelsRanker(),
        floor: Double = 0.45,
        wideningThreshold: Double = 0.6
    ) {
        self.scorer = scorer
        self.catalog = catalog
        self.ranker = ranker
        self.floor = floor
        self.wideningThreshold = wideningThreshold
    }

    public func match(name: String, notes: String) async -> MatchResult {
        let shortlist = scorer.candidates(for: name)

        if ranker.isAvailable {
            let candidates = isWeak(shortlist) ? wholeCatalogue : shortlist
            if let result = await ranked(name: name, notes: notes, candidates: candidates) {
                return result
            }
            // A cancelled task must not quietly produce a decision.
            if Task.isCancelled { return Self.cancelled }
        }
        return stageOne(shortlist)
    }

    /// Returned when the task was cancelled: nothing was decided, so nothing
    /// should be stored as a decision.
    private static let cancelled = MatchResult(choice: ArtChoice.unmatched, alternatives: [])

    private func isWeak(_ shortlist: [ScoredCandidate]) -> Bool {
        guard let top = shortlist.first else { return true }
        return top.score < wideningThreshold
    }

    private var wholeCatalogue: [ScoredCandidate] {
        catalog.entries.map { ScoredCandidate(entry: $0, score: 0) }
    }

    /// `nil` means the ranker could not give a usable answer and stage 1
    /// should decide; an empty answer from a working ranker is a real
    /// "none of these".
    private func ranked(
        name: String,
        notes: String,
        candidates: [ScoredCandidate]
    ) async -> MatchResult? {
        guard !candidates.isEmpty else { return nil }
        let slugs: [String]
        do {
            slugs = try await ranker.rank(name: name, notes: notes, candidates: candidates)
        } catch is CancellationError {
            return Self.cancelled
        } catch {
            logger.error("Ranker failed, using stage 1: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        if slugs.isEmpty { return MatchResult(choice: ArtChoice.none, alternatives: []) }

        // Discard anything the model made up or repeated.
        let allowed = Set(candidates.map(\.entry.slug))
        var seen = Set<String>()
        let valid = slugs.filter { allowed.contains($0) && seen.insert($0).inserted }
        guard let best = valid.first else {
            logger.error("Ranker returned only unknown slugs, using stage 1")
            return nil
        }
        return MatchResult(
            choice: ArtChoice.library(slug: best),
            alternatives: Array(valid.dropFirst().prefix(Self.maxAlternatives))
        )
    }

    private func stageOne(_ shortlist: [ScoredCandidate]) -> MatchResult {
        guard let top = shortlist.first, top.score >= floor else {
            // Stage 1 alone is not a decision that there is no picture: it runs when the
            // ranker is unavailable or gave no usable answer. `.none` is reserved for a
            // decision (an available ranker declining, or the user), so this stays
            // `.unmatched` and a later pass can retry.
            return MatchResult(choice: ArtChoice.unmatched, alternatives: [])
        }
        let alternatives = shortlist.dropFirst()
            .filter { $0.score >= floor }
            .prefix(Self.maxAlternatives)
            .map(\.entry.slug)
        return MatchResult(choice: ArtChoice.library(slug: top.entry.slug), alternatives: Array(alternatives))
    }
}

// MARK: - Test and fallback rankers

/// Returns fixed slugs. For tests and previews.
public struct StubRanker: CandidateRanker {
    private let slugs: [String]
    public let isAvailable: Bool

    public init(slugs: [String], isAvailable: Bool = true) {
        self.slugs = slugs
        self.isAvailable = isAvailable
    }

    public func rank(name: String, notes: String, candidates: [ScoredCandidate]) async throws -> [String] {
        slugs
    }
}

public struct RankerFailure: Error, Equatable {
    public init() {}
}

/// Available, but every call fails.
public struct ThrowingRanker: CandidateRanker {
    public let isAvailable = true

    public init() {}

    public func rank(name: String, notes: String, candidates: [ScoredCandidate]) async throws -> [String] {
        throw RankerFailure()
    }
}

/// Returns fixed slugs and remembers how many candidates it was handed.
public actor RecordingRanker: CandidateRanker {
    private let slugs: [String]
    public private(set) var lastCandidateCount = 0

    public nonisolated let isAvailable: Bool

    public init(slugs: [String], isAvailable: Bool = true) {
        self.slugs = slugs
        self.isAvailable = isAvailable
    }

    public func rank(name: String, notes: String, candidates: [ScoredCandidate]) async throws -> [String] {
        lastCandidateCount = candidates.count
        return slugs
    }
}
