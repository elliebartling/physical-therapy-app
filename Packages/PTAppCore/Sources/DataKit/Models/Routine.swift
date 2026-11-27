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
    /// The pause between exercises for this routine; nil uses the app's setting.
    /// Read it through `transitionSeconds`.
    public var transitionStorage: Int? = nil

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

    /// Seconds between exercises: nil follows the app's setting, 0 waits for a tap,
    /// and a negative number goes straight on.
    public var transitionSeconds: Int? {
        get { transitionStorage }
        set { transitionStorage = newValue }
    }
}
