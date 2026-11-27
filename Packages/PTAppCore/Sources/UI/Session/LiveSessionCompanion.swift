import ActivityKit
import Foundation
import LiveSession
import os

private let logger = Logger(subsystem: "PTAppCore", category: "live-session")

/// Keeps a guided session going outside the app: a Health workout session so it runs
/// in the background, and a Live Activity with its countdown and Pause and Next buttons.
@MainActor
public final class LiveSessionCompanion {
    private let keeper: WorkoutSessionKeeper
    /// The running Live Activity's id. The activity itself is looked up where it's used,
    /// so it never crosses from the main actor into ActivityKit's async calls.
    private var activityID: String?
    private var lastState: SessionActivityAttributes.ContentState?
    /// The workout session is running, so the session carries on in the background.
    public private(set) var runsInBackground = false

    public init(keeper: WorkoutSessionKeeper = WorkoutSessionKeeper()) {
        self.keeper = keeper
    }

    /// Starts the workout session (when allowed) and the Live Activity, and routes the
    /// activity's buttons to `onCommand`.
    public func begin(routineName: String, accentHex: UInt32, state: SessionActivityAttributes.ContentState,
                      onCommand: @escaping (LiveSessionCommands.Command) -> Void) async {
        LiveSessionCommands.shared.handler = onCommand
        if SessionPreferences.keepsRunningInBackground() {
            runsInBackground = await keeper.start(kind: HealthPreferences.load().kind)
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activityID = try Activity.request(
                attributes: SessionActivityAttributes(routineName: routineName, accentHex: accentHex),
                content: ActivityContent(state: state, staleDate: nil)
            ).id
            lastState = state
        } catch {
            logger.error("Starting the Live Activity failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Shows the session's current step. Repeats of the same state are dropped.
    public func update(_ state: SessionActivityAttributes.ContentState) {
        guard let activityID, state != lastState else { return }
        lastState = state
        Task { await Self.push(state, to: activityID) }
    }

    /// Ends the Live Activity and the workout session. `saveWorkout` keeps the workout in
    /// Health; otherwise it's thrown away. Returns whether the workout session handled
    /// Health, so the caller doesn't save a second workout.
    @discardableResult
    public func finish(at end: Date, saveWorkout: Bool) async -> Bool {
        LiveSessionCommands.shared.handler = nil
        if let activityID {
            self.activityID = nil
            await Self.endActivity(activityID)
        }
        guard runsInBackground else { return false }
        runsInBackground = false
        await keeper.end(at: end, save: saveWorkout)
        return true
    }

    private nonisolated static func push(_ state: SessionActivityAttributes.ContentState, to id: String) async {
        guard let activity = Activity<SessionActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    private nonisolated static func endActivity(_ id: String) async {
        guard let activity = Activity<SessionActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
