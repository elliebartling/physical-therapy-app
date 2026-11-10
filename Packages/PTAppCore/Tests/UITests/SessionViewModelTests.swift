import XCTest
import DataKit
import SessionKit
@testable import UI

@MainActor
final class SessionViewModelTests: XCTestCase {
    func test_runToCompletion_persistsSessionRecord() async throws {
        let container = try ModelContainerFactory.inMemory()
        let routineRepo = RoutineRepository(context: container.mainContext)
        let sessionRepo = SessionRepository(context: container.mainContext)

        let routine = Routine(name: "T", exercises: [
            Exercise(name: "X", target: .timeSets(seconds: 1, sets: 1), restSeconds: 0, side: .both, order: 0)
        ])
        try routineRepo.save(routine)

        let clock = TestClock()
        let vm = SessionViewModel(routine: routine, sessionRepo: sessionRepo, clock: clock,
                                  audio: nil, haptics: nil)
        await vm.run()
        try await Task.sleep(nanoseconds: 50_000_000) // drain final events
        XCTAssertEqual(try sessionRepo.fetchAll().count, 1)
        XCTAssertNotNil(try sessionRepo.fetchAll().first?.completedAt)

        _ = container // keep alive
    }
}
