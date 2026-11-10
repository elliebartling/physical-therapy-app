import Foundation
import SwiftData

@Model
public final class Routine {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var createdAt: Date
    public var isActive: Bool
    @Relationship(deleteRule: .cascade) public var exercises: [Exercise]

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        isActive: Bool = true,
        exercises: [Exercise] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.isActive = isActive
        self.exercises = exercises
    }

    public var orderedExercises: [Exercise] { exercises.sorted { $0.order < $1.order } }
}
