import Foundation
import HealthKit
import Observation

/// Runs a HealthKit workout session on the watch for the duration of a
/// PT session: live heart rate while exercising, and a workout saved to
/// Health when it ends.
@MainActor
@Observable
final class WatchWorkoutManager: NSObject {
    var heartRate: Double = 0

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func start() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(
                toShare: [HKObjectType.workoutType()],
                read: [
                    HKQuantityType(.heartRate),
                    HKQuantityType(.activeEnergyBurned)
                ]
            )

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .functionalStrengthTraining
            configuration.locationType = .indoor

            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            builder.delegate = self

            self.session = session
            self.builder = builder

            session.startActivity(with: .now)
            try await builder.beginCollection(at: .now)
        } catch {
            // The guided session still works without heart rate / HealthKit.
        }
    }

    func end() async {
        guard let session, let builder else { return }
        session.end()
        do {
            try await builder.endCollection(at: .now)
            try await builder.finishWorkout()
        } catch {
            // Nothing actionable on the watch; the phone log is the source of truth.
        }
        self.session = nil
        self.builder = nil
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(heartRateType),
              let statistics = workoutBuilder.statistics(for: heartRateType),
              let value = statistics.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) else {
            return
        }
        Task { @MainActor in
            self.heartRate = value
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
