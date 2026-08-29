import Foundation
import HealthKit

final class HealthKitManager: @unchecked Sendable {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()

    private init() {}

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(
            toShare: [HKObjectType.workoutType()],
            read: [HKObjectType.workoutType()]
        )
    }

    /// Logs a completed PT session as a workout in Apple Health.
    func saveWorkout(start: Date, end: Date, routineName: String) async throws {
        guard isAvailable else { return }
        try await requestAuthorization()

        // HealthKit rejects zero/negative-duration workouts.
        let safeEnd = end > start ? end : start.addingTimeInterval(60)

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)
        try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "Mend · \(routineName)"])
        try await builder.endCollection(at: safeEnd)
        try await builder.finishWorkout()
    }
}
