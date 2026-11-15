import Foundation
import HealthKit
import HistoryKit

/// Where other workouts come from. Apple Health in the app; a fake in tests.
public protocol WorkoutReader: Sendable {
    var isAvailable: Bool { get }
    /// Asks to read workouts. Health never says whether reading was allowed, so this
    /// only reports whether the request went through.
    func requestReadAccess() async throws
    /// Workouts that started in the range, newest first, leaving out Mend's own.
    func workouts(from start: Date, to end: Date) async throws -> [OtherWorkout]
}

/// Reads workouts from Apple Health. Only reads; it never changes them.
public final class HealthKitWorkoutReader: WorkoutReader, @unchecked Sendable {
    // HKHealthStore is documented as thread-safe; nothing else is stored.
    private let store = HKHealthStore()
    private let ownBundleID = Bundle.main.bundleIdentifier

    public init() {}

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func requestReadAccess() async throws {
        try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
    }

    public func workouts(from start: Date, to end: Date) async throws -> [OtherWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1000
        )
        let found = try await query.result(for: store)
        return found
            .filter { $0.sourceRevision.source.bundleIdentifier != ownBundleID }
            .map { workout in
                OtherWorkout(id: workout.uuid,
                             activity: WorkoutActivity(workout.workoutActivityType),
                             start: workout.startDate,
                             end: workout.endDate,
                             distanceMeters: Self.distance(of: workout))
            }
    }

    private static func distance(of workout: HKWorkout) -> Double? {
        let types: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        for identifier in types {
            if let sum = workout.statistics(for: HKQuantityType(identifier))?.sumQuantity() {
                return sum.doubleValue(for: .meter())
            }
        }
        return nil
    }
}

extension WorkoutActivity {
    /// The kinds people pick from when saying what a workout covers.
    public static let catalog: [WorkoutActivity] = [
        HKWorkoutActivityType.yoga, .pilates, .flexibility, .mindAndBody, .barre, .taiChi,
        .coreTraining, .functionalStrengthTraining, .traditionalStrengthTraining, .highIntensityIntervalTraining,
        .walking, .running, .hiking, .cycling, .swimming, .elliptical, .rowing, .stairClimbing, .socialDance,
    ].map { WorkoutActivity($0) }

    init(_ type: HKWorkoutActivityType) {
        let (name, tag): (String, String) = switch type {
        case .running: ("Running", "RUN")
        case .walking: ("Walking", "WALK")
        case .hiking: ("Hiking", "HIKE")
        case .cycling: ("Cycling", "BIKE")
        case .swimming: ("Swimming", "SWIM")
        case .yoga: ("Yoga", "YOGA")
        case .pilates: ("Pilates", "PILATES")
        case .flexibility: ("Flexibility", "STRETCH")
        case .mindAndBody: ("Mind and body", "MIND")
        case .barre: ("Barre", "BARRE")
        case .taiChi: ("Tai chi", "TAI CHI")
        case .coreTraining: ("Core training", "CORE")
        case .functionalStrengthTraining: ("Functional strength", "LIFT")
        case .traditionalStrengthTraining: ("Strength training", "LIFT")
        case .highIntensityIntervalTraining: ("HIIT", "HIIT")
        case .elliptical: ("Elliptical", "ELLIP")
        case .rowing: ("Rowing", "ROW")
        case .stairClimbing: ("Stair climbing", "STAIRS")
        case .socialDance, .cardioDance: ("Dance", "DANCE")
        case .preparationAndRecovery: ("Recovery", "REC")
        case .tennis: ("Tennis", "TENNIS")
        case .soccer: ("Soccer", "SOCCER")
        case .basketball: ("Basketball", "BBALL")
        case .golf: ("Golf", "GOLF")
        case .climbing: ("Climbing", "CLIMB")
        case .crossTraining: ("Cross training", "CROSS")
        case .mixedCardio: ("Mixed cardio", "CARDIO")
        case .pickleball: ("Pickleball", "PICKLE")
        default: ("Workout", "OTHER")
        }
        self.init(id: type.rawValue, name: name, tag: tag)
    }
}
