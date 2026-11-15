import Foundation
import HealthKit

/// What a session is saved to Apple Health as. The person picks one in Settings.
public enum HealthWorkoutKind: String, CaseIterable, Identifiable, Sendable {
    case recovery, functionalStrength, flexibility, coreTraining, pilates, yoga

    public var id: Self { self }

    public var title: String {
        switch self {
        case .recovery: "Recovery"
        case .functionalStrength: "Functional strength"
        case .flexibility: "Flexibility"
        case .coreTraining: "Core training"
        case .pilates: "Pilates"
        case .yoga: "Yoga"
        }
    }

    var activityType: HKWorkoutActivityType {
        switch self {
        case .recovery: .preparationAndRecovery
        case .functionalStrength: .functionalStrengthTraining
        case .flexibility: .flexibility
        case .coreTraining: .coreTraining
        case .pilates: .pilates
        case .yoga: .yoga
        }
    }
}

/// The person's Apple Health choices. Each is off until they turn it on in Settings.
public struct HealthPreferences: Equatable, Sendable {
    public static let enabledKey = "healthSyncEnabled"
    public static let kindKey = "healthWorkoutKind"
    public static let readsWorkoutsKey = "healthReadsWorkouts"
    public static let countsTowardGoalKey = "otherWorkoutsCountTowardGoal"

    /// Saving sessions to Health.
    public var isEnabled: Bool
    public var kind: HealthWorkoutKind
    /// Reading other workouts from Health.
    public var readsWorkouts: Bool
    /// Days with another workout count toward the weekly goal and streak. On unless turned off.
    public var countsTowardGoal: Bool

    public init(isEnabled: Bool = false, kind: HealthWorkoutKind = .recovery, readsWorkouts: Bool = false,
                countsTowardGoal: Bool = true) {
        self.isEnabled = isEnabled
        self.kind = kind
        self.readsWorkouts = readsWorkouts
        self.countsTowardGoal = countsTowardGoal
    }

    public static func load(from defaults: UserDefaults = .standard) -> HealthPreferences {
        HealthPreferences(
            isEnabled: defaults.bool(forKey: enabledKey),
            kind: defaults.string(forKey: kindKey).flatMap(HealthWorkoutKind.init(rawValue:)) ?? .recovery,
            readsWorkouts: defaults.bool(forKey: readsWorkoutsKey),
            countsTowardGoal: defaults.object(forKey: countsTowardGoalKey) as? Bool ?? true
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Self.enabledKey)
        defaults.set(kind.rawValue, forKey: Self.kindKey)
        defaults.set(readsWorkouts, forKey: Self.readsWorkoutsKey)
        defaults.set(countsTowardGoal, forKey: Self.countsTowardGoalKey)
    }
}
