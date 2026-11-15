import XCTest
@testable import DataKit

final class HowToSectionTests: XCTestCase {
    private func exercise() -> Exercise {
        Exercise(name: "X", target: .repsSets(reps: 1, sets: 1), restSeconds: 0, side: .both)
    }

    func test_sectionsRoundTripThroughTheModel() {
        let e = exercise()
        e.sheetHowTo = [HowToSection(heading: "Setup", body: "Begin standing behind a slant board.")]
        XCTAssertEqual(e.sheetHowTo.map(\.heading), ["Setup"])
    }

    func test_defaultsToNoSections() {
        XCTAssertEqual(exercise().sheetHowTo, [])
    }

    func test_orderAndVerbatimHeadingsSurvive() {
        let e = exercise()
        let sections = [
            HowToSection(heading: "Starting position", body: "a"),
            HowToSection(heading: "Tip", body: "b"),
            HowToSection(heading: "Movement", body: "c"),
        ]
        e.sheetHowTo = sections
        XCTAssertEqual(e.sheetHowTo, sections)
    }

    func test_garbageStoredDataReadsAsEmpty() {
        let e = exercise()
        e.sheetHowToData = Data([0xFF, 0x00])
        XCTAssertEqual(e.sheetHowTo, [])
    }

    func test_settingNoSectionsClearsThem() {
        let e = exercise()
        e.sheetHowTo = [HowToSection(heading: "Tip", body: "x")]
        e.sheetHowTo = []
        XCTAssertEqual(e.sheetHowTo, [])
    }

    func test_howToIsSeparateFromNotes() {
        let e = exercise()
        e.notes = "mine"
        e.sheetHowTo = [HowToSection(heading: "Tip", body: "x")]
        XCTAssertEqual(e.notes, "mine")
    }
}
