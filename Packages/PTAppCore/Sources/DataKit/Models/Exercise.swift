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
    /// Shared by the same exercise across routine versions. Optional so stores
    /// from before versioning migrate; read it through `lineageID`.
    public var lineageStorage: UUID?
    /// Raw `ArtChoice`. Optional so stores from before illustrations migrate;
    /// read it through `art`.
    public var artRaw: String?

    public init(
        id: UUID = UUID(),
        name: String,
        target: ExerciseTarget,
        restSeconds: Int,
        side: Side,
        notes: String = "",
        order: Int = 0,
        media: [Asset] = [],
        lineageID: UUID? = nil,
        art: ArtChoice = .unmatched
    ) {
        self.id = id
        self.name = name
        self.targetData = (try? JSONEncoder().encode(target)) ?? Data()
        self.restSeconds = restSeconds
        self.sideRaw = side.rawValue
        self.notes = notes
        self.order = order
        self.media = media
        self.lineageStorage = lineageID
        self.artRaw = art.rawValue
    }

    /// The same exercise across phases: history and charts group by this.
    /// An exercise that has never been carried over is its own lineage.
    public var lineageID: UUID {
        get { lineageStorage ?? id }
        set { lineageStorage = newValue }
    }

    public var target: ExerciseTarget {
        get { (try? JSONDecoder().decode(ExerciseTarget.self, from: targetData)) ?? .repsSets(reps: 0, sets: 0) }
        set { targetData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    public var side: Side {
        get { Side(rawValue: sideRaw) ?? .both }
        set { sideRaw = newValue.rawValue }
    }

    /// Which illustration to show; `.unmatched` when unset or unrecognised.
    public var art: ArtChoice {
        get { artRaw.flatMap(ArtChoice.init(rawValue:)) ?? .unmatched }
        set { artRaw = newValue.rawValue }
    }
}
