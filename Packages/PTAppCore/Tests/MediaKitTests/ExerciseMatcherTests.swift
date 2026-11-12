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
        let m = ExerciseMatcher(ranker: StubRanker(slugs: [], isAvailable: false))
        let r = await m.match(name: "Quadruped Opposite Arm/Leg Raise", notes: "")
        XCTAssertEqual(r.choice, ArtChoice.none)
    }

    func test_rankerThrowingFallsBackToStageOne() async {
        let m = ExerciseMatcher(ranker: ThrowingRanker())
        let r = await m.match(name: "Bird Dog", notes: "")
        XCTAssertEqual(r.choice, ArtChoice.library(slug: "bird-dog"))
    }

    func test_slugNotInShortlistIsDiscarded() async {
        let m = ExerciseMatcher(ranker: StubRanker(slugs: ["totally-made-up"]))
        let r = await m.match(name: "Bird Dog", notes: "")
        XCTAssertNotEqual(r.choice, ArtChoice.library(slug: "totally-made-up"))
        XCTAssertFalse(r.alternatives.contains("totally-made-up"))
    }

    func test_discardedSlugsDoNotPoisonValidOnes() async {
        let m = ExerciseMatcher(ranker: StubRanker(slugs: ["totally-made-up", "bird-dog"]))
        let r = await m.match(name: "Bird Dog", notes: "")
        XCTAssertEqual(r.choice, ArtChoice.library(slug: "bird-dog"))
        XCTAssertTrue(r.alternatives.isEmpty)
    }
}
