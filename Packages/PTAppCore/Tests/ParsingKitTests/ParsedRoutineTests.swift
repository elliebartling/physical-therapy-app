import XCTest
import DataKit
@testable import ParsingKit

final class ParsedRoutineTests: XCTestCase {
    func test_toRoutine_mapsExercisesInOrder() {
        let parsed = ParsedRoutine(name: "Knee", exercises: [
            .init(name: "Squat", reps: 12, sets: 3, durationSec: nil, restSec: 30, side: "both", notes: ""),
            .init(name: "Plank", reps: nil, sets: 2, durationSec: 30, restSec: 20, side: "both", notes: ""),
        ])
        let routine = parsed.toRoutine()
        XCTAssertEqual(routine.exercises.count, 2)
        let ordered = routine.exercises.sorted { $0.order < $1.order }
        XCTAssertEqual(ordered[0].target, .repsSets(reps: 12, sets: 3))
        XCTAssertEqual(ordered[1].target, .timeSets(seconds: 30, sets: 2))
        XCTAssertEqual(ordered[0].side, .both)
    }

    func test_toRoutineCarriesArtChoice() {
        let parsed = ParsedRoutine(name: "R", exercises: [
            .init(name: "Bird Dog", reps: 10, sets: 3, durationSec: nil, restSec: 30,
                  side: "both", notes: "", art: .library(slug: "bird-dog")),
            .init(name: "Mystery", reps: 10, sets: 3, durationSec: nil, restSec: 30,
                  side: "both", notes: "", art: .none),
        ])
        XCTAssertEqual(parsed.toRoutine().orderedExercises.map(\.art),
                       [.library(slug: "bird-dog"), .none])
    }

    func test_decodingWithoutArtDefaultsToUnmatched() throws {
        let json = #"{"name":"R","exercises":[{"name":"X","sets":3,"restSec":30,"side":"both","notes":""}]}"#
        let parsed = try JSONDecoder().decode(ParsedRoutine.self, from: Data(json.utf8))
        XCTAssertEqual(parsed.exercises[0].art, .unmatched)
        XCTAssertEqual(parsed.exercises[0].sheetHowTo, [])
    }

    func test_allThreeConversionsCarrySheetHowTo() {
        let section = HowToSection(heading: "Tip", body: "Keep your heels down.")
        let parsed = ParsedRoutine(name: "R", exercises: [
            .init(name: "X", reps: 1, sets: 1, durationSec: nil, restSec: 0, side: "both",
                  notes: "", sheetHowTo: [section]),
        ])
        let routine = parsed.toRoutine()
        XCTAssertEqual(routine.orderedExercises.first?.sheetHowTo, [section])
        XCTAssertEqual(ParsedRoutine(routine: routine).exercises.first?.sheetHowTo, [section])
        var draft = ParsedRoutine(routine: routine)
        draft.exercises[0].name = "Y"
        draft.apply(to: routine)
        XCTAssertEqual(routine.orderedExercises.first?.sheetHowTo, [section])
    }

    func test_applyToAnExistingExercise_writesAChangedSheetHowTo() {
        let old = HowToSection(heading: "Tip", body: "Old.")
        let new = HowToSection(heading: "Setup", body: "New.")
        let routine = ParsedRoutine(name: "R", exercises: [
            .init(name: "X", reps: 1, sets: 1, durationSec: nil, restSec: 0, side: "both",
                  notes: "", sheetHowTo: [old]),
        ]).toRoutine()
        var draft = ParsedRoutine(routine: routine)
        draft.exercises[0].sheetHowTo = [new]
        draft.apply(to: routine)
        XCTAssertEqual(routine.orderedExercises.first?.sheetHowTo, [new])
        draft.exercises[0].sheetHowTo = []
        draft.apply(to: routine)
        XCTAssertEqual(routine.orderedExercises.first?.sheetHowTo, [])
    }

    func test_applyCreatingANewExerciseCarriesSheetHowTo() {
        let section = HowToSection(heading: "Setup", body: "Stand.")
        let routine = Routine(name: "R", exercises: [])
        let draft = ParsedRoutine(name: "R", exercises: [
            .init(name: "New", reps: 1, sets: 1, durationSec: nil, restSec: 0, side: "both",
                  notes: "", sheetHowTo: [section]),
        ])
        draft.apply(to: routine)
        XCTAssertEqual(routine.orderedExercises.first?.sheetHowTo, [section])
    }

    func test_sheetHowToDoesNotLeakIntoNotes() {
        // Exercise.notes renders beside the running timer; sheet prose must never reach it.
        let parsed = ParsedRoutine(name: "R", exercises: [
            .init(name: "X", reps: 1, sets: 1, durationSec: nil, restSec: 0, side: "both", notes: "",
                  sheetHowTo: [HowToSection(heading: "Tip", body: "Keep your heels down.")]),
        ])
        let routine = parsed.toRoutine()
        XCTAssertEqual(routine.orderedExercises.first?.notes, "")
        XCTAssertEqual(ParsedRoutine(routine: routine).exercises.first?.notes, "")
        var draft = ParsedRoutine(routine: routine)
        draft.exercises[0].name = "Y"
        draft.apply(to: routine)
        XCTAssertEqual(routine.orderedExercises.first?.notes, "")
    }
}
