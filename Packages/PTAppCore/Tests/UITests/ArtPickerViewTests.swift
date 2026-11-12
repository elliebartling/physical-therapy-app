import XCTest
import SwiftUI
import ViewInspector
import DataKit
import MediaKit
import ParsingKit
@testable import UI

@MainActor
final class ArtPickerViewTests: XCTestCase {
    private func exercise(art: ArtChoice = .unmatched) -> ParsedRoutine.ParsedExercise {
        var ex = ParsedRoutine.ParsedExercise(name: "Bird Dog", reps: 10, sets: 3, durationSec: nil,
                                              restSec: 30, side: "both", notes: "")
        ex.art = art
        return ex
    }

    func test_pickerOffersNoPictureImmediately() throws {
        var art = ArtChoice.unmatched
        let v = ArtPickerView(art: Binding(get: { art }, set: { art = $0 }),
                              exerciseName: "Bird Dog",
                              matcher: ExerciseMatcher(ranker: StubRanker(slugs: ["bird-dog", "dead-bug"])))
        XCTAssertNoThrow(try v.inspect().find(text: "No picture"))
    }

    func test_choosingNoPictureSetsNone() throws {
        var art = ArtChoice.library(slug: "bird-dog")
        let v = ArtPickerView(art: Binding(get: { art }, set: { art = $0 }), exerciseName: "Bird Dog")
        try v.inspect().find(button: "No picture").tap()
        XCTAssertEqual(art, ArtChoice.none)
    }

    func test_suggestionsAreChoiceThenAlternatives_dropStaleSlugs() {
        let result = MatchResult(choice: .library(slug: "bird-dog"),
                                 alternatives: ["not-in-any-catalogue", "dead-bug"])
        let slugs = ArtPickerView.suggestions(from: result).map(\.slug)
        XCTAssertEqual(slugs, ["bird-dog", "dead-bug"])
    }

    func test_suggestionsWithNoMatchAreJustAlternatives() {
        let result = MatchResult(choice: .unmatched, alternatives: ["dead-bug"])
        XCTAssertEqual(ArtPickerView.suggestions(from: result).map(\.slug), ["dead-bug"])
    }

    func test_loadSuggestionsRunsTheMatcherOnDemand() async {
        let matcher = ExerciseMatcher(ranker: StubRanker(slugs: ["bird-dog", "dead-bug"]))
        let entries = await ArtPickerView.loadSuggestions(name: "Bird Dog", matcher: matcher)
        XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(entries.first?.slug, "bird-dog")
    }

    func test_choosingASuggestionSetsLibraryArt() throws {
        var art = ArtChoice.unmatched
        let entry = try XCTUnwrap(ExerciseCatalog.bundled.entry(slug: "bird-dog"))
        let v = ArtPickerView(art: Binding(get: { art }, set: { art = $0 }),
                              exerciseName: "Bird Dog", initialSuggestions: [entry])
        try v.inspect().find(button: entry.name).tap()
        XCTAssertEqual(art, .library(slug: "bird-dog"))
    }

    func test_editorShowsThePictureSection() throws {
        var ex = exercise()
        let v = ExerciseEditorView(exercise: Binding(get: { ex }, set: { ex = $0 }))
        XCTAssertNoThrow(try v.inspect().find(text: "Picture"))
    }

    func test_editorLinksToThePicker() throws {
        var ex = exercise()
        let v = ExerciseEditorView(exercise: Binding(get: { ex }, set: { ex = $0 }))
        XCTAssertNoThrow(try v.inspect().find(ViewType.NavigationLink.self, where: {
            (try? $0.view(ArtPickerView.self, 0)) != nil
        }))
    }

    // Both entry points (SetupView and EditRoutineView) host RoutineEditorView,
    // so reaching the editor from it covers both.
    func test_routineEditorRowsLinkToTheExerciseEditor() throws {
        let vm = RoutineEditorViewModel(name: "R", exercises: [exercise()])
        let v = RoutineEditorView(viewModel: vm, onSave: {})
        XCTAssertNoThrow(try v.inspect().find(ViewType.NavigationLink.self, where: {
            (try? $0.view(ExerciseEditorView.self, 0)) != nil
        }))
    }

    func test_addExerciseStartsUnmatched() {
        let vm = RoutineEditorViewModel(name: "R", exercises: [])
        vm.addExercise()
        XCTAssertEqual(vm.exercises.first?.art, ArtChoice.unmatched)
    }
}
