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
    /// How it felt, if the person rated it. Optional so older records migrate as-is.
    public var ratingRaw: String? = nil

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

    public var rating: ExerciseRating? {
        get { ratingRaw.flatMap(ExerciseRating.init(rawValue:)) }
        set { ratingRaw = newValue?.rawValue }
    }

    public var status: Status {
        get { Status(rawValue: statusRaw) ?? .partial }
        set { statusRaw = newValue.rawValue }
    }
}
