import Foundation
import DataKit

/// When to ask how exercises felt. Ratings are always optional.
public enum RatingTiming: String, CaseIterable, Identifiable, Sendable {
    case atEnd, afterEach, off

    public static let storageKey = "ratingTiming"

    public var id: Self { self }

    public var title: String {
        switch self {
        case .atEnd: "At the end"
        case .afterEach: "After each exercise"
        case .off: "Off"
        }
    }

    public static func load(from defaults: UserDefaults = .standard) -> RatingTiming {
        defaults.string(forKey: storageKey).flatMap(RatingTiming.init(rawValue:)) ?? .atEnd
    }
}

extension ExerciseRating {
    public var title: String {
        switch self {
        case .easy: "Easy"
        case .aboutRight: "About right"
        case .hard: "Hard"
        case .painful: "Painful"
        }
    }
}
