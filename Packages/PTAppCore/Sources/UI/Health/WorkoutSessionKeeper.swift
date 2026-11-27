import Foundation
import HealthKit
import os

private let logger = Logger(subsystem: "PTAppCore", category: "workout-session")

/// Runs a guided session as an Apple Health workout session, which is what lets iOS
/// keep Mend running, timer and all, when the person switches apps.
///
/// The workout is saved at the end only when saving to Health is on; otherwise it's
/// discarded. Needs permission to record workouts; without it, nothing starts and the
/// session pauses in the background as before.
public final class WorkoutSessionKeeper: @unchecked Sendable {
    // HKHealthStore is documented as thread-safe. The session and builder are only
    // touched from `start` and `end`, which the one running session calls in order.
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    public init() {}

    /// Starts the workout session. Returns whether it's running.
    public func start(kind: HealthWorkoutKind) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let workouts = HKObjectType.workoutType()
        do {
            if store.authorizationStatus(for: workouts) == .notDetermined {
                try await store.requestAuthorization(toShare: [workouts], read: [])
            }
            guard store.authorizationStatus(for: workouts) == .sharingAuthorized else { return false }

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = kind.activityType
            configuration.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            let start = Date.now
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            self.session = session
            self.builder = builder
            return true
        } catch {
            logger.error("Starting a workout session failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Ends the workout session, saving the workout to Health or throwing it away.
    public func end(at end: Date, save: Bool) async {
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        session.end()
        do {
            try await builder.endCollection(at: end)
            if save {
                _ = try await builder.finishWorkout()
            } else {
                builder.discardWorkout()
            }
        } catch {
            logger.error("Ending a workout session failed: \(String(describing: error), privacy: .public)")
        }
    }
}
