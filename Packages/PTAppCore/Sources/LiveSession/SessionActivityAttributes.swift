import ActivityKit
import Foundation

/// A guided session on the Lock Screen and in the Dynamic Island.
public struct SessionActivityAttributes: ActivityAttributes {
    /// What the session is doing now. Sent on each change of step, pause or resume;
    /// countdowns tick on their own from `endsAt`.
    public struct ContentState: Codable, Hashable, Sendable {
        /// "Bird Dog", "Rest" or "Up next: Bird Dog".
        public var title: String
        /// "SET 1/3 — LEFT SIDE", or the next exercise's prescription.
        public var detail: String
        /// When the current hold, rest or pause ends, while it's counting.
        public var endsAt: Date?
        /// Seconds left, frozen, while paused.
        public var remainingSeconds: Int?
        /// The reps to do, for a reps set.
        public var reps: Int?
        public var isPaused: Bool
        /// Exercises done out of the session, 0–1.
        public var progress: Double

        public init(title: String, detail: String, endsAt: Date? = nil, remainingSeconds: Int? = nil,
                    reps: Int? = nil, isPaused: Bool = false, progress: Double = 0) {
            self.title = title
            self.detail = detail
            self.endsAt = endsAt
            self.remainingSeconds = remainingSeconds
            self.reps = reps
            self.isPaused = isPaused
            self.progress = progress
        }
    }

    public var routineName: String
    /// The person's accent, as 0xRRGGBB, so the activity matches the app.
    public var accentHex: UInt32

    public init(routineName: String, accentHex: UInt32) {
        self.routineName = routineName
        self.accentHex = accentHex
    }
}
