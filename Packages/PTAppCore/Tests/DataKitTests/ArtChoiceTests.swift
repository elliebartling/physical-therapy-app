import XCTest
@testable import DataKit

final class ArtChoiceTests: XCTestCase {
    func test_rawValueRoundTripsAllCases() {
        for c in [ArtChoice.unmatched, .none, .library(slug: "bird-dog")] {
            XCTAssertEqual(ArtChoice(rawValue: c.rawValue), c)
        }
    }

    func test_unknownRawValueIsNil() {
        XCTAssertNil(ArtChoice(rawValue: "wat"))
        XCTAssertNil(ArtChoice(rawValue: "library:"))
    }

    func test_exerciseDefaultsToUnmatched() {
        let e = Exercise(name: "Bird Dog", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both)
        XCTAssertEqual(e.art, .unmatched)
    }

    func test_exerciseArtSurvivesAssignment() {
        let e = Exercise(name: "Bird Dog", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both)
        e.art = .library(slug: "bird-dog")
        XCTAssertEqual(e.art, .library(slug: "bird-dog"))
        e.art = .none
        XCTAssertEqual(e.art, .none)
    }

    func test_codableUsesRawString() throws {
        let data = try JSONEncoder().encode(ArtChoice.library(slug: "bird-dog"))
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"library:bird-dog\"")
        XCTAssertEqual(try JSONDecoder().decode(ArtChoice.self, from: data), .library(slug: "bird-dog"))
    }
}
