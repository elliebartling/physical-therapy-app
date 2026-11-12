import Foundation

/// A catalogue entry with its stage-1 lexical similarity to a parsed name.
public struct ScoredCandidate: Sendable, Equatable {
    public let entry: CatalogEntry
    /// `0...1`. Near 1 means the names share essentially all their words;
    /// low values mean only incidental words overlap.
    public let score: Double

    public init(entry: CatalogEntry, score: Double) {
        self.entry = entry
        self.score = score
    }
}

/// Cheap local shortlist of plausible catalogue entries for a parsed exercise
/// name.
///
/// Names are lower-cased and split into letter-only tokens; digits and handout
/// noise ("sets", "reps", "right", "page"...) are dropped and plurals are
/// folded. The score is the F1 of two IDF-weighted coverages: how much of the
/// query is explained by the entry, and how much of the entry is present in the
/// query. Rare words ("clamshell") count for more than common ones ("raise",
/// "push"), and query words unknown to the catalogue still count against the
/// match. This bridges wording differences only; it cannot bridge vocabulary
/// differences ("Quadruped Opposite Arm/Leg Raise" vs "Bird Dog") and reports
/// that honestly as a low score.
public struct CandidateScorer: Sendable {
    private struct Indexed: Sendable {
        let entry: CatalogEntry
        let tokens: Set<String>
    }

    private let indexed: [Indexed]
    private let weights: [String: Double]
    private let unknownWeight: Double

    public init(catalog: ExerciseCatalog = .bundled) {
        let indexed = catalog.entries.map {
            Indexed(entry: $0, tokens: Set(Self.tokens(in: $0.name)))
        }
        var documentFrequency: [String: Int] = [:]
        for item in indexed {
            for token in item.tokens { documentFrequency[token, default: 0] += 1 }
        }
        let count = Double(max(indexed.count, 1))
        self.indexed = indexed
        self.weights = documentFrequency.mapValues { log(1 + count / Double($0)) }
        self.unknownWeight = log(1 + count)
    }

    public func candidates(for name: String, limit: Int = 8) -> [ScoredCandidate] {
        let query = Set(Self.tokens(in: name))
        guard !query.isEmpty, limit > 0 else { return [] }
        let queryTotal = query.reduce(0) { $0 + weight(of: $1) }

        var scored: [(offset: Int, candidate: ScoredCandidate)] = []
        for (offset, item) in indexed.enumerated() {
            let shared = query.intersection(item.tokens)
            guard !shared.isEmpty else { continue }
            let sharedWeight = shared.reduce(0) { $0 + weight(of: $1) }
            let entryTotal = item.tokens.reduce(0) { $0 + weight(of: $1) }
            let precision = sharedWeight / queryTotal
            let recall = sharedWeight / entryTotal
            let score = 2 * precision * recall / (precision + recall)
            scored.append((offset, ScoredCandidate(entry: item.entry, score: min(max(score, 0), 1))))
        }

        // Equal scores keep catalogue order.
        scored.sort {
            $0.candidate.score != $1.candidate.score
                ? $0.candidate.score > $1.candidate.score
                : $0.offset < $1.offset
        }
        return scored.prefix(limit).map(\.candidate)
    }

    private func weight(of token: String) -> Double {
        weights[token] ?? unknownWeight
    }

    private static let noise: Set<String> = [
        "a", "an", "and", "the", "of", "with", "to", "for", "in", "on", "or",
        "x", "set", "sets", "rep", "reps", "right", "left", "bilateral", "each",
        "per", "page", "sec", "secs", "second", "seconds", "min", "mins",
        "minute", "minutes", "daily", "times", "time", "day", "days", "week",
    ]

    /// Letter-only tokens, noise removed, trivial plurals folded.
    static func tokens(in text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter })
            .map { singular(String($0)) }
            .filter { $0.count > 1 && !noise.contains($0) }
    }

    private static func singular(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        return String(word.dropLast())
    }
}
