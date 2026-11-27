import Foundation

/// Choices about how a guided session feels, set in Settings.
public enum SessionPreferences {
    public static let countdownHapticsKey = "countdownHaptics"

    /// A light tap on each of the last three seconds of a hold or rest. On unless turned off.
    public static func countdownHaptics(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: countdownHapticsKey) as? Bool ?? true
    }
}
