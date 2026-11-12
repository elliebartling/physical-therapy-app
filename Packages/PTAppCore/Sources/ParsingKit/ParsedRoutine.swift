import Foundation
import DataKit

public struct ParsedRoutine: Codable, Sendable, Equatable {
    public struct ParsedExercise: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var name: String
        public var reps: Int?
        public var sets: Int
        public var durationSec: Int?
        public var restSec: Int
        public var side: String
        public var notes: String
        public var art: ArtChoice
        /// The handout's own instruction prose; never merged into `notes`.
        public var sheetHowTo: [HowToSection]

        public init(id: UUID = UUID(), name: String, reps: Int?, sets: Int, durationSec: Int?, restSec: Int, side: String, notes: String, art: ArtChoice = .unmatched, sheetHowTo: [HowToSection] = []) {
            self.id = id
            self.name = name
            self.reps = reps
            self.sets = sets
            self.durationSec = durationSec
            self.restSec = restSec
            self.side = side
            self.notes = notes
            self.art = art
            self.sheetHowTo = sheetHowTo
        }

        private enum CodingKeys: String, CodingKey {
            case id, name, reps, sets, durationSec, restSec, side, notes, art, sheetHowTo
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
            self.name = try c.decode(String.self, forKey: .name)
            self.reps = try c.decodeIfPresent(Int.self, forKey: .reps)
            self.sets = try c.decode(Int.self, forKey: .sets)
            self.durationSec = try c.decodeIfPresent(Int.self, forKey: .durationSec)
            self.restSec = try c.decode(Int.self, forKey: .restSec)
            self.side = try c.decode(String.self, forKey: .side)
            self.notes = try c.decode(String.self, forKey: .notes)
            self.art = (try? c.decode(ArtChoice.self, forKey: .art)) ?? .unmatched
            self.sheetHowTo = (try? c.decode([HowToSection].self, forKey: .sheetHowTo)) ?? []
        }
    }

    public var name: String
    public var exercises: [ParsedExercise]

    public init(name: String, exercises: [ParsedExercise]) {
        self.name = name
        self.exercises = exercises
    }

    public func toRoutine() -> Routine {
        let mapped = exercises.enumerated().map { (idx, p) -> Exercise in
            let target: ExerciseTarget
            if let dur = p.durationSec {
                target = .timeSets(seconds: dur, sets: p.sets)
            } else {
                target = .repsSets(reps: p.reps ?? 0, sets: p.sets)
            }
            let side = Side(rawValue: p.side.lowercased()) ?? .both
            return Exercise(
                name: p.name,
                target: target,
                restSeconds: p.restSec,
                side: side,
                notes: p.notes,
                order: idx,
                art: p.art,
                sheetHowTo: p.sheetHowTo
            )
        }
        return Routine(name: name, exercises: mapped)
    }
}
