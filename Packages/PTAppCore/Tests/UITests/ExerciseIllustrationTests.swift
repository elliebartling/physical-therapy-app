import XCTest
import SwiftUI
import ViewInspector
import DataKit
@testable import UI

@MainActor
final class ExerciseIllustrationTests: XCTestCase {
    private static let credit = "Exercise illustrations by Bryl Lim, licensed CC BY-SA 4.0. Derived from Everkinetic."

    func test_clamp_keepsFramesWithinOneToThree() {
        XCTAssertEqual(ExerciseIllustration.clamped(0), 1)
        XCTAssertEqual(ExerciseIllustration.clamped(2), 2)
        XCTAssertEqual(ExerciseIllustration.clamped(9), 3)
    }

    func test_afterAFrameLoads_showsScrubAndCredit() throws {
        let sut = ExerciseIllustration(art: .library(slug: "bird-dog"), hasLoadedPicture: true)
        let texts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        XCTAssertTrue(texts.contains(Self.credit))
        XCTAssertNoThrow(try sut.inspect().find(ViewType.Picker.self))
    }

    func test_withoutAPicture_showsNothingAtAll() throws {
        for art in [ArtChoice.unmatched, ArtChoice.none, .library(slug: "no-such-slug")] {
            let sut = ExerciseIllustration(art: art)
            XCTAssertThrowsError(try sut.inspect().find(text: Self.credit), "\(art)")
            XCTAssertThrowsError(try sut.inspect().find(ViewType.Picker.self), "\(art)")
        }
    }

    func test_beforeAnyFrameLoads_catalogueKnownSlugShowsNeitherScrubNorCredit() throws {
        let sut = ExerciseIllustration(art: .library(slug: "bird-dog"))
        XCTAssertThrowsError(try sut.inspect().find(text: Self.credit))
        XCTAssertThrowsError(try sut.inspect().find(ViewType.Picker.self))
    }
}
