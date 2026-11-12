import Foundation

/// How an exercise felt. Always optional.
public enum ExerciseRating: String, CaseIterable, Codable, Sendable {
    case easy, aboutRight, hard, painful
}
