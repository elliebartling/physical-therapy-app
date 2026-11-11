import Foundation
import HealthKit

/// One session, as Apple Health will see it.
public struct WorkoutSample: Equatable, Sendable {
    public let kind: HealthWorkoutKind
    public let start: Date
    public let end: Date
    /// Logged after the fact rather than timed in the app.
    public let wasLoggedLater: Bool
}

/// Where workouts are saved. Apple Health in the app; a fake in tests.
public protocol WorkoutStore: Sendable {
    var isAvailable: Bool { get }
    /// Asks to save workouts. Returns whether saving is allowed.
    func requestAccess() async throws -> Bool
    func save(_ sample: WorkoutSample) async throws
}

/// Saves workouts to Apple Health. Writes only; Mend never reads Health data.
public final class HealthKitWorkoutStore: WorkoutStore, @unchecked Sendable {
    // HKHealthStore is documented as thread-safe; nothing else is stored.
    private let store = HKHealthStore()

    public init() {}

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func requestAccess() async throws -> Bool {
        let workouts = HKObjectType.workoutType()
        try await store.requestAuthorization(toShare: [workouts], read: [])
        return store.authorizationStatus(for: workouts) == .sharingAuthorized
    }

    public func save(_ sample: WorkoutSample) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = sample.kind.activityType
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: sample.start)
        if sample.wasLoggedLater {
            try await builder.addMetadata([HKMetadataKeyWasUserEntered: true])
        }
        try await builder.endCollection(at: sample.end)
        _ = try await builder.finishWorkout()
    }
}
