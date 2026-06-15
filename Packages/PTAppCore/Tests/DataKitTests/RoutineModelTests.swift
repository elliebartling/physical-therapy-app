import XCTest
import SwiftData
@testable import DataKit

final class RoutineModelTests: XCTestCase {
    @MainActor
    func test_routinePersistsExercisesInOrder() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Routine.self, Exercise.self, Asset.self,
            configurations: config
        )
        let ctx = container.mainContext

        let r = Routine(name: "Morning")
        r.exercises = [
            Exercise(name: "Squat", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both, order: 0),
            Exercise(name: "Plank", target: .timeSets(seconds: 30, sets: 2), restSeconds: 20, side: .both, order: 1),
        ]
        ctx.insert(r)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Routine>()).first
        let ordered = (fetched?.exercises ?? []).sorted { $0.order < $1.order }
        XCTAssertEqual(ordered.map(\.name), ["Squat", "Plank"])
        XCTAssertEqual(ordered.first?.target, .repsSets(reps: 10, sets: 3))
    }
}
