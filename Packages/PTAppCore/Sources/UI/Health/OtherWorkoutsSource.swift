import Foundation
import HistoryKit
import os

private let logger = Logger(subsystem: "PTAppCore", category: "health")

/// Workouts from outside Mend, read from Apple Health when the person has turned
/// that on, plus what they've said each kind of workout covers.
@MainActor
public final class OtherWorkoutsSource {
    static let rulesKey = "coverageRules"
    static let dismissedKey = "dismissedWorkoutIDs"
    /// Dismissed offers remembered, newest kept.
    static let dismissedLimit = 100

    private let reader: any WorkoutReader
    private let defaults: UserDefaults

    public init(reader: any WorkoutReader = HealthKitWorkoutReader(), defaults: UserDefaults = .standard) {
        self.reader = reader
        self.defaults = defaults
    }

    /// Reading is turned on and Health is available on this device.
    public var isOn: Bool { HealthPreferences.load(from: defaults).readsWorkouts && reader.isAvailable }

    /// Workouts that started in the range, newest first. Empty when reading is off; a
    /// failed read is logged and also comes back empty, since it only adds context.
    public func workouts(from start: Date, to end: Date) async -> [OtherWorkout] {
        guard isOn else { return [] }
        do {
            return try await reader.workouts(from: start, to: end)
        } catch {
            logger.error("Reading workouts from Health failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    // MARK: Coverage rules

    public var rules: [CoverageRule] {
        guard let data = defaults.data(forKey: Self.rulesKey) else { return [] }
        do {
            return try JSONDecoder().decode([CoverageRule].self, from: data)
        } catch {
            logger.error("Reading coverage rules failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    public func rule(for activityID: UInt) -> CoverageRule? {
        rules.first { $0.activity.id == activityID }
    }

    /// Adds the rule, or replaces the one for the same kind of workout.
    public func save(_ rule: CoverageRule) {
        var all = rules.filter { $0.activity.id != rule.activity.id }
        all.append(rule)
        store(all.sorted { $0.activity.name < $1.activity.name })
    }

    public func removeRule(for activityID: UInt) {
        store(rules.filter { $0.activity.id != activityID })
    }

    private func store(_ rules: [CoverageRule]) {
        do {
            defaults.set(try JSONEncoder().encode(rules), forKey: Self.rulesKey)
        } catch {
            logger.error("Saving coverage rules failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Offers

    /// Don't offer this workout again.
    public func dismiss(_ workoutID: UUID) {
        var ids = defaults.stringArray(forKey: Self.dismissedKey) ?? []
        ids.append(workoutID.uuidString)
        defaults.set(Array(ids.suffix(Self.dismissedLimit)), forKey: Self.dismissedKey)
    }

    public func isDismissed(_ workoutID: UUID) -> Bool {
        (defaults.stringArray(forKey: Self.dismissedKey) ?? []).contains(workoutID.uuidString)
    }
}
