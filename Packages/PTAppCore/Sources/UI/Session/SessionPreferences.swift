import Foundation

/// Choices about how a guided session feels, set in Settings.
public enum SessionPreferences {
    public static let countdownHapticsKey = "countdownHaptics"
    public static let transitionSecondsKey = "transitionSeconds"
    public static let announceNextKey = "announceNext"
    /// Ten seconds to get into position, unless changed.
    public static let defaultTransitionSeconds = 10

    /// A light tap on each of the last three seconds of a hold or rest. On unless turned off.
    public static func countdownHaptics(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: countdownHapticsKey) as? Bool ?? true
    }

    /// The pause between exercises: see `SessionTransition(seconds:)`.
    public static func transitionSeconds(in defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: transitionSecondsKey) as? Int ?? defaultTransitionSeconds
    }

    /// Say what's next aloud. On unless turned off.
    public static func announcesNext(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: announceNextKey) as? Bool ?? true
    }
}
