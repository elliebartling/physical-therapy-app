import Foundation
import DataKit

public struct ParsedRoutine: Codable, Sendable, Equatable {
    public struct ParsedExercise: Codable, Sendable, Equatable {
        public var name: String
        public var reps: Int?
        public var sets: Int
        public var durationSec: Int?
        public var restSec: Int
        public var side: String
        public var notes: String

        public init(name: String, reps: Int?, sets: Int, durationSec: Int?, restSec: Int, side: String, notes: String) {
            self.name = name
            self.reps = reps
            self.sets = sets
            self.durationSec = durationSec
            self.restSec = restSec
            self.side = side
            self.notes = notes
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
                order: idx
            )
        }
        return Routine(name: name, exercises: mapped)
    }
}
