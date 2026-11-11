import XCTest
import DataKit
@testable import ParsingKit

final class ParsedRoutineEditingTests: XCTestCase {
    private func routine() -> Routine {
        Routine(name: "Knee", exercises: [
            Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both, order: 0),
            Exercise(name: "Side plank", target: .timeSets(seconds: 20, sets: 3), restSeconds: 15,
                     side: .alternating, notes: "Hips up", order: 1),
        ])
    }

    func test_draftFromRoutine_keepsIdsOrderAndTargets() {
        let r = routine()
        let draft = ParsedRoutine(routine: r)

        XCTAssertEqual(draft.name, "Knee")
        XCTAssertEqual(draft.exercises.map(\.id), r.orderedExercises.map(\.id))
        XCTAssertEqual(draft.exercises[0].reps, 10)
        XCTAssertNil(draft.exercises[0].durationSec)
        XCTAssertEqual(draft.exercises[1].durationSec, 20)
        XCTAssertEqual(draft.exercises[1].side, "alternating")
        XCTAssertEqual(draft.exercises[1].notes, "Hips up")
    }

    func test_apply_updatesInPlace_addsNew_andReportsRemoved() {
        let r = routine()
        let bridgesID = r.orderedExercises[0].id
        let plankID = r.orderedExercises[1].id

        var draft = ParsedRoutine(routine: r)
        draft.name = "Knee, Phase 3"
        draft.exercises[0].reps = 15                          // edit Bridges
        draft.exercises.remove(at: 1)                         // drop Side plank
        draft.exercises.append(.init(name: "Single-leg bridge", reps: 8, sets: 3, durationSec: nil,
                                     restSec: 30, side: "alternating", notes: ""))

        let removed = draft.apply(to: r)

        XCTAssertEqual(r.name, "Knee, Phase 3")
        XCTAssertEqual(removed.map(\.id), [plankID])
        let ordered = r.orderedExercises
        XCTAssertEqual(ordered.map(\.name), ["Bridges", "Single-leg bridge"])
        XCTAssertEqual(ordered[0].id, bridgesID, "edited exercise keeps its identity")
        XCTAssertEqual(ordered[0].target, .repsSets(reps: 15, sets: 3))
        XCTAssertEqual(ordered[1].side, .alternating)
        XCTAssertEqual(ordered.map(\.order), [0, 1])
    }

    func test_apply_reorder_rewritesOrder() {
        let r = routine()
        var draft = ParsedRoutine(routine: r)
        draft.exercises.reverse()

        draft.apply(to: r)

        XCTAssertEqual(r.orderedExercises.map(\.name), ["Side plank", "Bridges"])
    }
}
