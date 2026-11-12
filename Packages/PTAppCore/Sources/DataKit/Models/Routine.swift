import Foundation
import SwiftData

@Model
public final class Routine {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var createdAt: Date
    public var isActive: Bool
    @Relationship(deleteRule: .cascade) public var exercises: [Exercise]
    /// Which version of the routine this is. Optional so older stores migrate; read it through `phase`.
    public var phaseStorage: Int?
    /// The routine this one replaced, when it came from a new sheet.
    public var previousVersionID: UUID?

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

    /// Phase 1 is the first sheet; each replacement adds one.
    public var phase: Int {
        get { phaseStorage ?? 1 }
        set { phaseStorage = newValue }
    }

    public var orderedExercises: [Exercise] { exercises.sorted { $0.order < $1.order } }
}
