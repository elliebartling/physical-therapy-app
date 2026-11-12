import XCTest
@testable import DataKit

final class RoutineChangesTests: XCTestCase {
    private func spec(_ name: String, reps: Int = 10, sets: Int = 3, rest: Int = 30, side: Side = .both) -> ExerciseSpec {
        ExerciseSpec(name: name, target: .repsSets(reps: reps, sets: sets), side: side, restSeconds: rest)
    }

    func test_sameName_ignoringCaseSpacingAndPunctuation_matches() {
        let changes = RoutineChanges(from: [spec("Clamshells")], to: [spec(" clam-shells ")])
        XCTAssertEqual(changes.items.map(\.kind), [.unchanged])
        XCTAssertEqual(changes.matches, [0: 0])
    }

    func test_newPrescription_isChanged() {
        let changes = RoutineChanges(from: [spec("Bridges", reps: 10)], to: [spec("Bridges", reps: 15)])
        XCTAssertEqual(changes.items.map(\.kind), [.changed])
        XCTAssertEqual(changes.items.first?.before?.target, .repsSets(reps: 10, sets: 3))
        XCTAssertEqual(changes.items.first?.after?.target, .repsSets(reps: 15, sets: 3))
    }

    func test_newRestOrSide_isChanged() {
        XCTAssertEqual(RoutineChanges(from: [spec("Bridges", rest: 30)], to: [spec("Bridges", rest: 45)]).items.map(\.kind), [.changed])
        XCTAssertEqual(RoutineChanges(from: [spec("Lunge")], to: [spec("Lunge", side: .alternating)]).items.map(\.kind), [.changed])
    }

    func test_countsAddedRemovedAndUnchanged_newOrderThenRemoved() {
        let changes = RoutineChanges(
            from: [spec("Bridges"), spec("Wall sit"), spec("Heel slides")],
            to: [spec("Step ups"), spec("Bridges"), spec("Wall sit", reps: 12)]
        )
        XCTAssertEqual(changes.items.map(\.name), ["Step ups", "Bridges", "Wall sit", "Heel slides"])
        XCTAssertEqual(changes.items.map(\.kind), [.added, .unchanged, .changed, .removed])
        XCTAssertEqual(changes.count(.added), 1)
        XCTAssertEqual(changes.count(.removed), 1)
        XCTAssertEqual(changes.matches, [1: 0, 2: 1])
        XCTAssertFalse(changes.isEmpty)
    }

    func test_duplicateNames_pairInOrder() {
        let changes = RoutineChanges(from: [spec("Stretch", reps: 1), spec("Stretch", reps: 2)],
                                     to: [spec("Stretch", reps: 1), spec("Stretch", reps: 2), spec("Stretch", reps: 3)])
        XCTAssertEqual(changes.matches, [0: 0, 1: 1])
        XCTAssertEqual(changes.items.map(\.kind), [.unchanged, .unchanged, .added])
    }

    func test_identicalSheet_isEmpty() {
        XCTAssertTrue(RoutineChanges(from: [spec("Bridges")], to: [spec("Bridges")]).isEmpty)
    }
}
