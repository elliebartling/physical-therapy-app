import Foundation
import SwiftData

@Model
public final class ExerciseRecord {
    public enum Status: String, Codable, Sendable { case completed, skipped, partial }

    @Attribute(.unique) public var id: UUID
    public var exerciseID: UUID
    public var statusRaw: String
    public var startedAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        exerciseID: UUID,
        status: Status,
        startedAt: Date,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.statusRaw = status.rawValue
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    public var status: Status {
        get { Status(rawValue: statusRaw) ?? .partial }
        set { statusRaw = newValue.rawValue }
    }
}
