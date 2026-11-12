import XCTest
@testable import MediaKit

final class CandidateScorerTests: XCTestCase {
    func test_exactNameScoresTop() {
        let s = CandidateScorer()
        XCTAssertEqual(s.candidates(for: "Bird Dog").first?.entry.slug, "bird-dog")
        XCTAssertEqual(s.candidates(for: "clamshell").first?.entry.slug, "clamshell")
    }

    func test_handoutPhrasingFindsTheRightFamily() {
        let s = CandidateScorer()
        // Real handout wording that shares tokens with the catalogue name.
        // The right answer need only be in the shortlist — stage 2 picks.
        let cases: [(String, String)] = [
            ("Side-Lying Hip Abduction - Right", "side-lying-hip-abduction"),
            ("Supine Glute Bridge x10", "glute-bridge"),
            ("Clamshells, 3 sets", "clamshell"),
        ]
        for (input, expected) in cases {
            let slugs = s.candidates(for: input).map(\.entry.slug)
            XCTAssertTrue(slugs.contains(expected), "\(input) → \(slugs)")
        }
    }

    func test_clinicalSynonymScoresLowAndMisses() {
        // "Quadruped Opposite Arm/Leg Raise" is how a handout names a bird dog.
        // It shares no token with "Bird Dog", and DOES share tokens with
        // "Lying Leg Raise" — so lexical scoring returns a plausible-looking
        // shortlist that cannot contain the right answer. Stage 1 must report
        // this honestly through a low top score; rescuing it is stage 2's job.
        let c = CandidateScorer().candidates(for: "Quadruped Opposite Arm/Leg Raise")
        XCTAssertFalse(c.map(\.entry.slug).contains("bird-dog"))
        XCTAssertLessThan(c.first?.score ?? 0, 0.6)
    }

    func test_garbageInputYieldsNoCandidates() {
        let s = CandidateScorer()
        for junk in ["", "   ", "Page 2 of 3", "11/04/2026", "Riverside Physical Therapy"] {
            XCTAssertTrue(s.candidates(for: junk).isEmpty, "\(junk)")
        }
    }

    func test_respectsLimit() {
        XCTAssertLessThanOrEqual(CandidateScorer().candidates(for: "squat", limit: 3).count, 3)
    }

    func test_scoresAreDescendingAndNormalised() {
        let c = CandidateScorer().candidates(for: "bridge")
        XCTAssertEqual(c, c.sorted { $0.score > $1.score })
        XCTAssertTrue(c.allSatisfy { (0...1).contains($0.score) })
    }

    func test_exactMatchScoresNearOneAndIncidentalWordScoresLow() {
        let s = CandidateScorer()
        XCTAssertGreaterThan(s.candidates(for: "Bird Dog").first?.score ?? 0, 0.95)
        XCTAssertLessThan(s.candidates(for: "Seated Cable Row Machine Pull").first?.score ?? 0, 0.5)
    }
}
