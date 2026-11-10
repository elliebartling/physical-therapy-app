import Foundation

public enum ExerciseTarget: Codable, Equatable, Sendable {
    case repsSets(reps: Int, sets: Int)
    case timeSets(seconds: Int, sets: Int)

    public var totalSets: Int {
        switch self {
        case .repsSets(_, let sets), .timeSets(_, let sets):
            return sets
        }
    }
}
