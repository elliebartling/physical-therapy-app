import Foundation

/// What happens between one exercise and the next.
public enum SessionTransition: Equatable, Sendable {
    /// Straight on to the next exercise.
    case none
    /// A countdown to get into position, skippable and pausable.
    case timed(seconds: Int)
    /// Wait until the person says they're ready.
    case manual

    /// From a stored setting: a negative number goes straight on, 0 waits, more counts down.
    public init(seconds: Int) {
        if seconds < 0 {
            self = .none
        } else if seconds == 0 {
            self = .manual
        } else {
            self = .timed(seconds: seconds)
        }
    }

    /// The routine's own setting when it has one, otherwise the app's.
    public static func resolve(routineSeconds: Int?, appSeconds: Int) -> SessionTransition {
        SessionTransition(seconds: routineSeconds ?? appSeconds)
    }

    /// The settings offered, in order.
    public static let choices = [0, 5, 10, 15, 20, 30, 45, 60, -1]

    public static func title(for seconds: Int) -> String {
        switch SessionTransition(seconds: seconds) {
        case .none: "No pause"
        case .manual: "Wait for me"
        case .timed(let seconds): "\(seconds) seconds"
        }
    }
}
