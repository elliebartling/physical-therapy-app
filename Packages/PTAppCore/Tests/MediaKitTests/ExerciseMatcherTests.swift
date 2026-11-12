import DataKit
import XCTest
@testable import MediaKit

final class ExerciseMatcherTests: XCTestCase {
    func test_rankerChoiceWins() async {
        let m = ExerciseMatcher(ranker: StubRanker(slugs: ["clamshell", "fire-hydrant"]))
        let r = await m.match(name: "Side-Lying Clam", notes: "")
        XCTAssertEqual(r.choice, ArtChoice.library(slug: "clamshell"))
        XCTAssertEqual(r.alternatives, ["fire-hydrant"])
    }

    func test_rankerSayingNoneYieldsNoPicture() async {
        let m = ExerciseMatcher(ranker: StubRanker(slugs: []))
        let r = await m.match(name: "Slant Board Gastrocnemius Stretch", notes: "")
        XCTAssertEqual(r.choice, ArtChoice.none)
    }

    func test_degradesToStageOneWhenModelUnavailable() async {
        let m = ExerciseMatcher(ranker: StubRanker(slugs: [], isAvailable: false))
        let r = await m.match(name: "Bird Dog", notes: "")
        XCTAssertEqual(r.choice, ArtChoice.library(slug: "bird-dog"))
    }

    func test_floorAppliesOnStageOneOnlyPath() async {
        // Model unavailable must not ship the least-bad slug.
        let m = ExerciseMatcher(ranker: StubRanker(slugs: [], isAvailable: false), floor: 0.99)
        let r = await m.match(name: "Slant Board Gastrocnemius Stretch", notes: "")
        XCTAssertEqual(r.choice, ArtChoice.none)
    }

    func test_clinicalSynonymIsRescuedByWidening() async {
        // Stage 1 cannot reach bird-dog from this name (see CandidateScorerTests).
        // Widening hands the whole catalogue to the ranker, which can.
        let ranker = RecordingRanker(slugs: ["bird-dog"])
        let m = ExerciseMatcher(ranker: ranker)
        let r = await m.match(name: "Quadruped Opposite Arm/Leg Raise", notes: "")
        XCTAssertEqual(r.choice, ArtChoice.library(slug: "bird-dog"))
        let count = await ranker.lastCandidateCount
        XCTAssertEqual(count, 142)
    }

    func test_strongShortlistIsNotWidened() async {
        let ranker = RecordingRanker(slugs: ["bird-dog"])
        let m = ExerciseMatcher(ranker: ranker)
        _ = await m.match(name: "Bird Dog", notes: "")
        let count = await ranker.lastCandidateCount
        XCTAssertLessThanOrEqual(count, 8)
        XCTAssertGreaterThan(count, 0)
    }

    func test_garbageNameEndsAsNoPictureWhenTheRankerDeclines() async {
        // Widening also fires here; the ranker answering "none of these" is what
        // makes it no picture, which is the honest outcome for page furniture.
        let m = ExerciseMatcher(ranker: StubRanker(slugs: []))
        let r = await m.match(name: "Page 2 of 3", notes: "")
        XCTAssertEqual(r.choice, ArtChoice.none)
        XCTAssertTrue(r.alternatives.isEmpty)
    }

    func test_noWideningWhenTheRankerIsUnavailable() async {
        let ranker = RecordingRanker(slugs: ["bird-dog"], isAvailable: false)
        let m = ExerciseMatcher(ranker: ranker)
        let r = await m.match(name: "Quadruped Opposite Arm/Leg Raise", notes: "")
        XCTAssertEqual(r.choice, ArtChoice.none)
        // Never called, so never handed the whole catalogue.
        let count = await ranker.lastCandidateCount
        XCTAssertEqual(count, 0)
    }

    func test_rankerDecliningOverridesAStrongStageOneMatch() async {
        // "Bird Dog" scores 1.0 in stage 1; the available ranker still has the last word.
        let m = ExerciseMatcher(ranker: StubRanker(slugs: []))
        let r = await m.match(name: "Bird Dog", notes: "")
        XCTAssertEqual(r.choice, ArtChoice.none)
        XCTAssertTrue(r.alternatives.isEmpty)
    }

    func test_cancellationIsNotTurnedIntoAFallbackDecision() async {
        let m = ExerciseMatcher(ranker: CancellingRanker())
        let r = await m.match(name: "Bird Dog", notes: "")
        XCTAssertEqual(r.choice, ArtChoice.unmatched)
    }

    func test_rankerAlternativesAreCappedAtThree() async {
        let slugs = ["clamshell", "fire-hydrant", "bird-dog", "glute-bridge", "squat"]
        // A threshold above any score always widens, so every slug is a candidate
        // whatever the scorer does.
        let m = ExerciseMatcher(ranker: StubRanker(slugs: slugs), wideningThreshold: 2)
        let r = await m.match(name: "Side-Lying Clam", notes: "")
        XCTAssertEqual(r.alternatives, ["fire-hydrant", "bird-dog", "glute-bridge"])
    }

    func test_rankerThrowingFallsBackToStageOne() async {
        let m = ExerciseMatcher(ranker: ThrowingRanker())
        let r = await m.match(name: "Bird Dog", notes: "")
        XCTAssertEqual(r.choice, ArtChoice.library(slug: "bird-dog"))
    }

    func test_slugNotInShortlistIsDiscarded() async {
        let m = ExerciseMatcher(ranker: StubRanker(slugs: ["totally-made-up"]))
        let r = await m.match(name: "Bird Dog", notes: "")
        // Nothing usable from the ranker: stage 1 decides, and "Bird Dog" clears the floor.
        XCTAssertEqual(r.choice, ArtChoice.library(slug: "bird-dog"))
        XCTAssertFalse(r.alternatives.contains("totally-made-up"))
    }

    func test_unusableRankerAnswerCannotShipBelowTheFloor() async {
        let m = ExerciseMatcher(ranker: StubRanker(slugs: ["totally-made-up"]))
        let r = await m.match(name: "Slant Board Gastrocnemius Stretch", notes: "")
        XCTAssertEqual(r.choice, ArtChoice.none)
    }

    func test_modelNumbersMapBackToSlugsAndOutOfRangeIsDropped() throws {
        let catalog = ExerciseCatalog.bundled.entries
        let candidates = catalog.prefix(5).map { ScoredCandidate(entry: $0, score: 0) }
        let ranking = GenerableRanking(reasoning: "", verdict: .same, choices: [3, 99, 0, 1])
        let slugs = try FoundationModelsRanker.slugs(from: ranking, candidates: candidates)
        XCTAssertEqual(slugs, [candidates[2].entry.slug, candidates[0].entry.slug])
    }

    func test_modelNoneVerdictIgnoresNumbers() throws {
        let candidates = ExerciseCatalog.bundled.entries.prefix(5).map { ScoredCandidate(entry: $0, score: 0) }
        let ranking = GenerableRanking(reasoning: "", verdict: .none, choices: [1])
        XCTAssertEqual(try FoundationModelsRanker.slugs(from: ranking, candidates: candidates), [])
    }

    func test_modelSameWithOnlyOutOfRangeNumbersFails() {
        let candidates = ExerciseCatalog.bundled.entries.prefix(5).map { ScoredCandidate(entry: $0, score: 0) }
        let ranking = GenerableRanking(reasoning: "", verdict: .same, choices: [42])
        XCTAssertThrowsError(try FoundationModelsRanker.slugs(from: ranking, candidates: candidates))
    }

    func test_widenedPromptStaysSmallAndNotesAreCapped() {
        let all = ExerciseCatalog.bundled.entries.map { ScoredCandidate(entry: $0, score: 0) }
        let prompt = FoundationModelsRanker.prompt(
            name: "Quadruped Opposite Arm/Leg Raise",
            notes: String(repeating: "n", count: 5000),
            candidates: all
        )
        XCTAssertLessThan(prompt.count, 7000)
        XCTAssertFalse(prompt.contains(String(repeating: "n", count: 201)))
        XCTAssertTrue(prompt.contains("\n\(all.count) | "))
    }

    func test_extremeModelNumbersDoNotTrapAndValidOnesSurvive() throws {
        let candidates = ExerciseCatalog.bundled.entries.prefix(5).map { ScoredCandidate(entry: $0, score: 0) }
        let ranking = GenerableRanking(
            reasoning: "", verdict: .same, choices: [Int.min, 2, Int.max, -1]
        )
        let slugs = try FoundationModelsRanker.slugs(from: ranking, candidates: candidates)
        XCTAssertEqual(slugs, [candidates[1].entry.slug])
    }

    func test_otherFailureInsideACancelledTaskIsNotAFallbackDecision() async {
        let task = Task {
            // Wait until cancelled, then let the ranker fail with an ordinary error.
            while !Task.isCancelled { await Task.yield() }
            let m = ExerciseMatcher(ranker: ThrowingRanker())
            return await m.match(name: "Bird Dog", notes: "")
        }
        task.cancel()
        let r = await task.value
        XCTAssertEqual(r.choice, ArtChoice.unmatched)
    }

    func test_discardedSlugsDoNotPoisonValidOnes() async {
        let m = ExerciseMatcher(ranker: StubRanker(slugs: ["totally-made-up", "bird-dog"]))
        let r = await m.match(name: "Bird Dog", notes: "")
        XCTAssertEqual(r.choice, ArtChoice.library(slug: "bird-dog"))
        XCTAssertTrue(r.alternatives.isEmpty)
    }
}

/// Always reports cancellation.
struct CancellingRanker: CandidateRanker {
    let isAvailable = true
    func rank(name: String, notes: String, candidates: [ScoredCandidate]) async throws -> [String] {
        throw CancellationError()
    }
}
