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

    @MainActor
    func test_ratingsPainAndNote_areOptionalAndPersist() throws {
        let container = try ModelContainerFactory.inMemory()
        let ctx = container.mainContext
        let rated = ExerciseRecord(exerciseID: UUID(), status: .completed, startedAt: .now, completedAt: .now)
        let unrated = ExerciseRecord(exerciseID: UUID(), status: .completed, startedAt: .now, completedAt: .now)
        let session = SessionRecord(routineID: UUID(), startedAt: .now, completedAt: .now,
                                    exerciseRecords: [rated, unrated])
        XCTAssertNil(session.painLevel)
        XCTAssertNil(session.note)
        XCTAssertNil(rated.rating)

        rated.rating = .hard
        session.painLevel = 3
        session.note = "Left knee clicked on bridges"
        ctx.insert(session)
        try ctx.save()

        let fetched = try XCTUnwrap(try ctx.fetch(FetchDescriptor<SessionRecord>()).first)
        XCTAssertEqual(fetched.painLevel, 3)
        XCTAssertEqual(fetched.note, "Left knee clicked on bridges")
        XCTAssertEqual(Set(fetched.exerciseRecords.map(\.rating)), [.hard, nil])
    }

    func test_unknownStoredRating_readsAsUnrated() {
        let record = ExerciseRecord(exerciseID: UUID(), status: .completed, startedAt: .now)
        record.ratingRaw = "fantastic"
        XCTAssertNil(record.rating)
    }
}
