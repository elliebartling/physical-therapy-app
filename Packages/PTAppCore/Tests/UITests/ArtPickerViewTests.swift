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
        // ViewInspector never runs `.task`, so this is the pre-suggestions state.
        var art = ArtChoice.unmatched
        let v = ArtPickerView(art: Binding(get: { art }, set: { art = $0 }), exerciseName: "Bird Dog")
        XCTAssertNoThrow(try v.inspect().find(text: "No picture"))
    }

    func test_currentChoiceAbsentFromSuggestionsIsStillListed() throws {
        let deadBug = try XCTUnwrap(ExerciseCatalog.bundled.entry(slug: "dead-bug"))
        let birdDog = try XCTUnwrap(ExerciseCatalog.bundled.entry(slug: "bird-dog"))
        let shown = ArtPickerView.displayedEntries(current: .library(slug: "bird-dog"), suggestions: [deadBug])
        XCTAssertEqual(shown.map(\.slug), [birdDog.slug, deadBug.slug])
    }

    func test_currentChoiceAlreadySuggestedIsNotDuplicated() throws {
        let birdDog = try XCTUnwrap(ExerciseCatalog.bundled.entry(slug: "bird-dog"))
        let shown = ArtPickerView.displayedEntries(current: .library(slug: "bird-dog"), suggestions: [birdDog])
        XCTAssertEqual(shown.map(\.slug), ["bird-dog"])
    }

    func test_currentChoiceShowsBeforeAnySuggestionsArrive() throws {
        let birdDog = try XCTUnwrap(ExerciseCatalog.bundled.entry(slug: "bird-dog"))
        var art = ArtChoice.library(slug: "bird-dog")
        let v = ArtPickerView(art: Binding(get: { art }, set: { art = $0 }), exerciseName: "x")
        XCTAssertNoThrow(try v.inspect().find(text: birdDog.name))
    }

    func test_pictureValueDescribesTheCurrentChoice() throws {
        let birdDog = try XCTUnwrap(ExerciseCatalog.bundled.entry(slug: "bird-dog"))
        XCTAssertEqual(ArtPickerView.pictureDescription(for: .library(slug: "bird-dog")), birdDog.name)
        XCTAssertEqual(ArtPickerView.pictureDescription(for: ArtChoice.none), "None")
        XCTAssertEqual(ArtPickerView.pictureDescription(for: .unmatched), "Not set")
        XCTAssertEqual(ArtPickerView.pictureDescription(for: .library(slug: "gone")), "Not set")
    }

    func test_editorPassesNotesToThePicker() throws {
        var ex = exercise()
        ex.notes = "on hands and knees"
        let v = ExerciseEditorView(exercise: Binding(get: { ex }, set: { ex = $0 }))
        let picker = try v.inspect().find(ViewType.NavigationLink.self, where: {
            (try? $0.view(ArtPickerView.self, 0)) != nil
        }).view(ArtPickerView.self, 0)
        XCTAssertEqual(try picker.actualView().notes, "on hands and knees")
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

    /// ViewInspector cannot run `.task`, so `isSeeded` is out of reach; but the seed lands in the
    /// picker's initial state, which its body renders. Without the pass-through the picker would
    /// show only "Finding suggestions…".
    func test_editorHandsTheImportedSuggestionsToThePicker() throws {
        var ex = exercise()
        let imported = ImportedSuggestions(name: ex.name, notes: ex.notes,
                                           result: MatchResult(choice: .library(slug: "bird-dog"),
                                                               alternatives: ["dead-bug"]))
        let v = ExerciseEditorView(exercise: Binding(get: { ex }, set: { ex = $0 }), imported: imported)
        let link = try v.inspect().find(ViewType.NavigationLink.self, where: {
            (try? $0.view(ArtPickerView.self, 0)) != nil
        })
        let picker = try link.view(ArtPickerView.self, 0)
        let deadBug = try XCTUnwrap(ExerciseCatalog.bundled.entry(slug: "dead-bug"))
        XCTAssertNoThrow(try picker.find(text: deadBug.name))
    }

    func test_importedSuggestionsAreServedOnlyWhileNameAndNotesMatch() {
        let imported = ImportedSuggestions(name: "Bird Dog", notes: "slow",
                                           result: MatchResult(choice: .library(slug: "bird-dog"),
                                                               alternatives: ["dead-bug"]))
        XCTAssertEqual(imported.entries(forName: "Bird Dog", notes: "slow").map(\.slug), ["bird-dog", "dead-bug"])
        XCTAssertTrue(imported.entries(forName: "Bird Dog (left)", notes: "slow").isEmpty)
        XCTAssertTrue(imported.entries(forName: "Bird Dog", notes: "").isEmpty)
    }

    /// A pin: a new exercise is `.unmatched` (retryable), never `.none`.
    func test_addExerciseStartsUnmatched() {
        let vm = RoutineEditorViewModel(name: "R", exercises: [])
        vm.addExercise()
        XCTAssertEqual(vm.exercises.first?.art, ArtChoice.unmatched)
    }
}
