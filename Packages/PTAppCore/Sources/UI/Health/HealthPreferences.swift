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

/// The person's Apple Health choices. Off until they turn it on in Settings.
public struct HealthPreferences: Equatable, Sendable {
    public static let enabledKey = "healthSyncEnabled"
    public static let kindKey = "healthWorkoutKind"

    public var isEnabled: Bool
    public var kind: HealthWorkoutKind

    public init(isEnabled: Bool = false, kind: HealthWorkoutKind = .recovery) {
        self.isEnabled = isEnabled
        self.kind = kind
    }

    public static func load(from defaults: UserDefaults = .standard) -> HealthPreferences {
        HealthPreferences(
            isEnabled: defaults.bool(forKey: enabledKey),
            kind: defaults.string(forKey: kindKey).flatMap(HealthWorkoutKind.init(rawValue:)) ?? .recovery
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Self.enabledKey)
        defaults.set(kind.rawValue, forKey: Self.kindKey)
    }
}
