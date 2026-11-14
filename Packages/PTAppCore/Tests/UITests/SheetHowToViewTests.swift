import XCTest
import SwiftUI
import ViewInspector
import DataKit
@testable import UI

@MainActor
final class SheetHowToViewTests: XCTestCase {
    private let sections = [
        HowToSection(heading: "Setup", body: "Begin by standing behind a slant board."),
        HowToSection(heading: "Starting position", body: "Heels down."),
        HowToSection(heading: "Tip", body: "Hold a wall for balance."),
    ]

    func test_showsHeadingThenBody_inSheetOrder_headingsVerbatim() throws {
        let sut = SheetHowToView(sections: sections)
        let texts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        XCTAssertEqual(texts, [
            "Setup", "Begin by standing behind a slant board.",
            "Starting position", "Heels down.",
            "Tip", "Hold a wall for balance.",
        ])
    }

    func test_noSections_rendersNothing() throws {
        let sut = SheetHowToView(sections: [])
        // A throw from inspect() fails the test; only "inspected fine, found no Text" passes.
        XCTAssertEqual(try sut.inspect().findAll(ViewType.Text.self).count, 0)
    }

    func test_emptyHeading_omitsTheHeadingAndShowsTheBody() throws {
        let sut = SheetHowToView(sections: [HowToSection(heading: "", body: "Heels down.")])
        let texts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        XCTAssertEqual(texts, ["Heels down."])
    }
}
