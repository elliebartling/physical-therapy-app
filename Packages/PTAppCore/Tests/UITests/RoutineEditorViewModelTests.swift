import XCTest
import ParsingKit
@testable import UI

@MainActor
final class RoutineEditorViewModelTests: XCTestCase {
    func test_addExercise_appendsBlank() {
        let vm = RoutineEditorViewModel(name: "T", exercises: [])
        vm.addExercise()
        XCTAssertEqual(vm.exercises.count, 1)
        XCTAssertEqual(vm.exercises[0].name, "New exercise")
    }

    func test_remove_thenMove_keepsOrdering() {
        let vm = RoutineEditorViewModel(name: "T", exercises: [
            .init(name: "A", reps: 1, sets: 1, durationSec: nil, restSec: 0, side: "both", notes: ""),
            .init(name: "B", reps: 1, sets: 1, durationSec: nil, restSec: 0, side: "both", notes: ""),
            .init(name: "C", reps: 1, sets: 1, durationSec: nil, restSec: 0, side: "both", notes: ""),
        ])
        vm.remove(at: IndexSet(integer: 1))
        vm.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(vm.exercises.map(\.name), ["C", "A"])
    }
}
