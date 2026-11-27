import AppIntents
import Foundation

/// Commands from the Live Activity's buttons. The intents run in the app's process,
/// where the running session listens.
@MainActor
public final class LiveSessionCommands {
    public enum Command: Sendable {
        case togglePause
        case next
    }

    public static let shared = LiveSessionCommands()

    /// Set by the running session; nil when there isn't one.
    public var handler: ((Command) -> Void)?

    public func send(_ command: Command) {
        handler?(command)
    }
}

/// Pauses or resumes the session from the Lock Screen or Dynamic Island.
public struct ToggleSessionPauseIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource { "Pause or resume" }

    public init() {}

    public func perform() async throws -> some IntentResult {
        await LiveSessionCommands.shared.send(.togglePause)
        return .result()
    }
}

/// Moves to the next step: finishes a reps set, or skips a hold, rest or pause.
public struct NextSessionStepIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource { "Next step" }

    public init() {}

    public func perform() async throws -> some IntentResult {
        await LiveSessionCommands.shared.send(.next)
        return .result()
    }
}
