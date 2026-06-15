import XCTest
import SwiftData
@testable import DataKit

@MainActor
final class SessionRepositoryTests: XCTestCase {
    // Retain the container for the test lifetime — ModelContext only holds a
    // weak ref to its container, so a returned-and-dropped container will be
    // deallocated mid-test and crash the next save/insert.
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainerFactory.inMemory()
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    func test_insertAndFetchByDateRange() throws {
        let repo = SessionRepository(context: container.mainContext)

        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let s1 = SessionRecord(routineID: UUID(), startedAt: today, completedAt: today)
        let s2 = SessionRecord(routineID: UUID(), startedAt: yesterday, completedAt: yesterday)
        try repo.insert(s1)
        try repo.insert(s2)

        XCTAssertEqual(try repo.fetchAll().count, 2)
        let range = try repo.fetch(from: yesterday, through: today.addingTimeInterval(86400))
        XCTAssertEqual(range.count, 2)
    }
}
