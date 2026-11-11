import XCTest
import DataKit
@testable import UI

@MainActor
final class EditRoutineViewModelTests: XCTestCase {
    func test_save_editsTheSameRoutine_soHistoryStaysAttached() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = RoutineRepository(context: container.mainContext)
        let routine = Routine(name: "Knee", exercises: [
            Exercise(name: "Hip abduction with resistance on platform", target: .repsSets(reps: 10, sets: 3),
                     restSeconds: 30, side: .both, order: 0),
            Exercise(name: "Wall sit", target: .timeSets(seconds: 30, sets: 3), restSeconds: 30, side: .both, order: 1),
        ])
        try repo.save(routine)
        let routineID = routine.id
        let hipID = routine.orderedExercises[0].id

        let vm = EditRoutineViewModel(routine: routine, repo: repo)
        XCTAssertEqual(vm.editor.exercises.first?.name, "Hip abduction with resistance on platform")

        vm.editor.name = "Knee, phase 2"
        vm.editor.exercises[0].reps = 12
        vm.editor.remove(at: IndexSet(integer: 1))
        XCTAssertTrue(vm.save())

        let saved = try XCTUnwrap(try repo.fetchActive())
        XCTAssertEqual(saved.id, routineID)
        XCTAssertEqual(try repo.fetchAll().count, 1, "editing must not create a second routine")
        XCTAssertEqual(saved.name, "Knee, phase 2")
        XCTAssertEqual(saved.orderedExercises.map(\.id), [hipID])
        XCTAssertEqual(saved.orderedExercises.first?.target, .repsSets(reps: 12, sets: 3))
        XCTAssertNil(vm.errorMessage)

        _ = container
    }

    func test_unsavedEdits_doNotTouchTheRoutine() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = RoutineRepository(context: container.mainContext)
        let routine = Routine(name: "Knee", exercises: [
            Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both, order: 0)
        ])
        try repo.save(routine)

        let vm = EditRoutineViewModel(routine: routine, repo: repo)
        vm.editor.name = "Changed my mind"
        vm.editor.addExercise()
        // Cancel = drop the view model without saving.

        XCTAssertEqual(routine.name, "Knee")
        XCTAssertEqual(routine.exercises.count, 1)

        _ = container
    }
}
