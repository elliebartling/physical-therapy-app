import Foundation
import os

private let logger = Logger(subsystem: "PTAppCore", category: "health")

/// Saves finished sessions to Apple Health when the person has turned that on.
///
/// The session is already saved in Mend by the time this runs, so a Health
/// failure is logged and otherwise ignored: there's nothing the person can do
/// about it mid-workout.
@MainActor
public final class HealthRecorder {
    private let store: any WorkoutStore
    private let preferences: @MainActor () -> HealthPreferences

    public init(store: any WorkoutStore = HealthKitWorkoutStore(),
                preferences: @escaping @MainActor () -> HealthPreferences = { .load() }) {
        self.store = store
        self.preferences = preferences
    }

    public func record(start: Date, end: Date, wasLoggedLater: Bool) async {
        let prefs = preferences()
        guard prefs.isEnabled, store.isAvailable, end > start else { return }
        let sample = WorkoutSample(kind: prefs.kind, start: start, end: end, wasLoggedLater: wasLoggedLater)
        do {
            try await store.save(sample)
        } catch {
            logger.error("Saving a workout to Health failed: \(String(describing: error), privacy: .public)")
        }
    }
}
