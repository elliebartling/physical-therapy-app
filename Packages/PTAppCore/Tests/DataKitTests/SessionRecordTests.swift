import XCTest
import SwiftData
@testable import DataKit

final class SessionRecordTests: XCTestCase {
    @MainActor
    func test_sessionRecordRelatesToExerciseRecords() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SessionRecord.self, ExerciseRecord.self,
            configurations: config
        )
        let ctx = container.mainContext

        let session = SessionRecord(routineID: UUID(), startedAt: .now)
        session.exerciseRecords = [
            ExerciseRecord(exerciseID: UUID(), status: .completed, startedAt: .now, completedAt: .now)
        ]
        ctx.insert(session)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<SessionRecord>()).first
        XCTAssertEqual(fetched?.exerciseRecords.count, 1)
        XCTAssertEqual(fetched?.exerciseRecords.first?.status, .completed)
    }
}
