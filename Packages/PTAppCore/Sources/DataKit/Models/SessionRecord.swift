import Foundation
import SwiftData

@Model
public final class SessionRecord {
    @Attribute(.unique) public var id: UUID
    public var routineID: UUID
    public var startedAt: Date
    public var completedAt: Date?
    @Relationship(deleteRule: .cascade) public var exerciseRecords: [ExerciseRecord]
    /// Pain from 0 to 10 after the session, if recorded.
    public var painLevel: Int? = nil
    /// A note for the PT, if any.
    public var note: String? = nil

    public init(
        id: UUID = UUID(),
        routineID: UUID,
        startedAt: Date,
        completedAt: Date? = nil,
        exerciseRecords: [ExerciseRecord] = []
    ) {
        self.id = id
        self.routineID = routineID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.exerciseRecords = exerciseRecords
    }

    public var isComplete: Bool { completedAt != nil }
}
