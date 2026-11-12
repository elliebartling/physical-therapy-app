import XCTest
import SwiftData
@testable import DataKit

@MainActor
final class RoutineRepositoryTests: XCTestCase {
    // Hold the container in test state so it isn't deallocated while the
    // context (which keeps only a weak ref) is still in use.
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainerFactory.inMemory()
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private func makeRepo() -> (RoutineRepository, ModelContext) {
        let ctx = container.mainContext
        return (RoutineRepository(context: ctx), ctx)
    }

    func test_saveAndFetchActive() throws {
        let (repo, _) = makeRepo()
        let r = Routine(name: "Knee rehab", exercises: [
            Exercise(name: "Wall sit", target: .timeSets(seconds: 30, sets: 3), restSeconds: 20, side: .both, order: 0)
        ])
        try repo.save(r)
        let active = try repo.fetchActive()
        XCTAssertEqual(active?.name, "Knee rehab")
        XCTAssertEqual(active?.exercises.count, 1)
    }

    func test_replacingActive_deactivatesPrevious() throws {
        let (repo, _) = makeRepo()
        try repo.save(Routine(name: "Old"))
        try repo.replaceActive(with: Routine(name: "New"))
        let active = try repo.fetchActive()
        XCTAssertEqual(active?.name, "New")
        XCTAssertEqual(try repo.fetchAll().count, 2)
        XCTAssertEqual(try repo.fetchAll().filter(\.isActive).count, 1)
    }

    func test_saveEdits_keepsRoutineIdentity_andDeletesRemovedExercises() throws {
        let (repo, ctx) = makeRepo()
        let wallSit = Exercise(name: "Wall sit", target: .timeSets(seconds: 30, sets: 3), restSeconds: 20, side: .both, order: 0)
        let bridges = Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both, order: 1)
        let routine = Routine(name: "Knee rehab", exercises: [wallSit, bridges])
        try repo.save(routine)
        let originalID = routine.id

        routine.name = "Knee rehab, phase 2"
        routine.exercises = [bridges]
        try repo.saveEdits(to: routine, removing: [wallSit])

        let active = try repo.fetchActive()
        XCTAssertEqual(active?.id, originalID)
        XCTAssertEqual(active?.name, "Knee rehab, phase 2")
        XCTAssertEqual(active?.exercises.map(\.name), ["Bridges"])
        XCTAssertEqual(try repo.fetchAll().count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Exercise>()).count, 1, "removed exercise is deleted, not orphaned")
    }

    func test_replaceActive_carriesLineageForMatchingNames_andStartsTheNextPhase() throws {
        let (repo, _) = makeRepo()
        let bridges = Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both, order: 0)
        let wallSit = Exercise(name: "Wall sit", target: .timeSets(seconds: 30, sets: 3), restSeconds: 20, side: .both, order: 1)
        let phase1 = Routine(name: "Knee", exercises: [bridges, wallSit])
        try repo.save(phase1)

        let newBridges = Exercise(name: "bridges", target: .repsSets(reps: 15, sets: 3), restSeconds: 30, side: .both, order: 0)
        let stepUps = Exercise(name: "Step ups", target: .repsSets(reps: 10, sets: 2), restSeconds: 30, side: .alternating, order: 1)
        try repo.replaceActive(with: Routine(name: "Knee", exercises: [newBridges, stepUps]))

        let active = try XCTUnwrap(repo.fetchActive())
        XCTAssertEqual(active.phase, 2)
        XCTAssertEqual(active.previousVersionID, phase1.id)
        XCTAssertEqual(newBridges.lineageID, bridges.lineageID)
        XCTAssertNotEqual(newBridges.id, bridges.id)
        XCTAssertEqual(stepUps.lineageID, stepUps.id)
        // The old phase stays, inactive, with the removed exercise still in it.
        XCTAssertFalse(phase1.isActive)
        XCTAssertEqual(try repo.fetchAll().count, 2)
        XCTAssertTrue(phase1.exercises.contains { $0.name == "Wall sit" })
    }

    func test_replaceActive_twice_keepsTheFirstLineage() throws {
        let (repo, _) = makeRepo()
        let original = Exercise(name: "Clamshells", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .left, order: 0)
        try repo.save(Routine(name: "Hip", exercises: [original]))
        try repo.replaceActive(with: Routine(name: "Hip", exercises: [
            Exercise(name: "Clamshells", target: .repsSets(reps: 12, sets: 3), restSeconds: 30, side: .left, order: 0)
        ]))
        let third = Exercise(name: "Clamshells", target: .repsSets(reps: 15, sets: 3), restSeconds: 30, side: .left, order: 0)
        try repo.replaceActive(with: Routine(name: "Hip", exercises: [third]))

        XCTAssertEqual(third.lineageID, original.id)
        XCTAssertEqual(try repo.fetchActive()?.phase, 3)
    }

    func test_firstRoutine_isPhaseOne_andEachExerciseIsItsOwnLineage() throws {
        let (repo, _) = makeRepo()
        let bridges = Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both, order: 0)
        try repo.replaceActive(with: Routine(name: "Knee", exercises: [bridges]))
        XCTAssertEqual(try repo.fetchActive()?.phase, 1)
        XCTAssertNil(try repo.fetchActive()?.previousVersionID)
        XCTAssertEqual(bridges.lineageID, bridges.id)
    }
}
