import XCTest
@testable import Mend

@MainActor
final class PlayerEngineTests: XCTestCase {
    private func routine(_ exercises: [ExercisePayload]) -> RoutinePayload {
        RoutinePayload(name: "Test", daysPerWeek: 3, exercises: exercises)
    }

    func testRepExerciseBuildsWorkAndRestSteps() {
        let payload = routine([
            ExercisePayload(name: "Bridges", sets: 3, reps: 10, restSeconds: 30)
        ])
        let steps = PlayerEngine.buildSteps(for: payload)
        // work, rest, work, rest, work — no trailing rest after the final set.
        XCTAssertEqual(steps.count, 5)
        XCTAssertEqual(steps.map(\.kind), [.work, .rest, .work, .rest, .work])
        XCTAssertEqual(steps[0].goal, .reps(10))
        XCTAssertEqual(steps[1].goal, .timed(30))
    }

    func testPerSideTimedExerciseAlternatesSides() {
        let payload = routine([
            ExercisePayload(name: "Side plank", sets: 2, reps: nil, holdSeconds: 20, restSeconds: 15, isPerSide: true)
        ])
        let steps = PlayerEngine.buildSteps(for: payload)
        let workSteps = steps.filter { $0.kind == .work }
        XCTAssertEqual(workSteps.count, 4)
        XCTAssertEqual(workSteps.map(\.side), ["Left", "Right", "Left", "Right"])
        XCTAssertTrue(workSteps.allSatisfy { $0.goal == .timed(20) })
    }

    func testZeroRestBuildsNoRestSteps() {
        let payload = routine([
            ExercisePayload(name: "Heel raises", sets: 2, reps: 15, restSeconds: 0)
        ])
        let steps = PlayerEngine.buildSteps(for: payload)
        XCTAssertEqual(steps.map(\.kind), [.work, .work])
    }

    func testCompletingStepsRecordsResults() {
        let payload = routine([
            ExercisePayload(name: "Bridges", sets: 2, reps: 10, restSeconds: 0),
            ExercisePayload(name: "Clamshells", sets: 1, reps: 12, restSeconds: 0)
        ])
        let engine = PlayerEngine(routine: payload)
        engine.start()

        // Complete both bridge sets, skip clamshells entirely.
        engine.completeCurrentStep()
        engine.completeCurrentStep()
        engine.skipCurrentStep()

        XCTAssertTrue(engine.isFinished)
        let results = engine.results(source: "phone")
        XCTAssertEqual(results.exercises.count, 2)
        XCTAssertEqual(results.exercises[0].completedSets, 2)
        XCTAssertEqual(results.exercises[0].totalReps, 20)
        XCTAssertFalse(results.exercises[0].skipped)
        XCTAssertEqual(results.exercises[1].completedSets, 0)
        XCTAssertTrue(results.exercises[1].skipped)
    }

    func testSkippingEverythingFinishesWithoutCredit() {
        let payload = routine([
            ExercisePayload(name: "Bridges", sets: 1, reps: 10, restSeconds: 0)
        ])
        let engine = PlayerEngine(routine: payload)
        engine.start()
        engine.skipCurrentStep()

        XCTAssertTrue(engine.isFinished)
        XCTAssertTrue(engine.results(source: "phone").exercises[0].skipped)
    }

    func testEstimatedDurationIsPositive() {
        let payload = routine([
            ExercisePayload(name: "Bridges", sets: 3, reps: 10, restSeconds: 30),
            ExercisePayload(name: "Plank", sets: 3, reps: nil, holdSeconds: 30, restSeconds: 30)
        ])
        XCTAssertGreaterThan(payload.estimatedSeconds, 0)
    }
}
