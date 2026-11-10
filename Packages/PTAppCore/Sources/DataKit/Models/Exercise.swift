import Foundation
import SwiftData

@Model
public final class Exercise {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var targetData: Data            // ExerciseTarget encoded as JSON for SwiftData
    public var restSeconds: Int
    public var sideRaw: String             // Side.rawValue
    public var notes: String
    public var order: Int
    @Relationship(deleteRule: .cascade) public var media: [Asset]

    public init(
        id: UUID = UUID(),
        name: String,
        target: ExerciseTarget,
        restSeconds: Int,
        side: Side,
        notes: String = "",
        order: Int = 0,
        media: [Asset] = []
    ) {
        self.id = id
        self.name = name
        self.targetData = (try? JSONEncoder().encode(target)) ?? Data()
        self.restSeconds = restSeconds
        self.sideRaw = side.rawValue
        self.notes = notes
        self.order = order
        self.media = media
    }

    public var target: ExerciseTarget {
        get { (try? JSONDecoder().decode(ExerciseTarget.self, from: targetData)) ?? .repsSets(reps: 0, sets: 0) }
        set { targetData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    public var side: Side {
        get { Side(rawValue: sideRaw) ?? .both }
        set { sideRaw = newValue.rawValue }
    }
}
