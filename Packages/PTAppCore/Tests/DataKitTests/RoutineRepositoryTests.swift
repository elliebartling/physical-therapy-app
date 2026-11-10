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
}
