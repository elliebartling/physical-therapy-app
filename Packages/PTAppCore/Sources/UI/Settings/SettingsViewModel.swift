import Foundation
import Observation
import os

private let logger = Logger(subsystem: "PTAppCore", category: "settings")

@MainActor
@Observable
public final class SettingsViewModel {
    public var reminderEnabled = false
    public var reminderTime: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now

    /// Saving sessions to Apple Health. Only turns on once the person allows it.
    public private(set) var healthEnabled: Bool
    /// Shown under the Health switch when turning it on didn't work.
    public private(set) var healthMessage: String?
    public var healthKind: HealthWorkoutKind {
        didSet { healthPreferences.save(to: defaults) }
    }

    private let scheduler = NotificationScheduler()
    private let workoutStore: any WorkoutStore
    private let defaults: UserDefaults

    public init(workoutStore: any WorkoutStore = HealthKitWorkoutStore(),
                defaults: UserDefaults = .standard) {
        self.workoutStore = workoutStore
        self.defaults = defaults
        let saved = HealthPreferences.load(from: defaults)
        self.healthEnabled = saved.isEnabled
        self.healthKind = saved.kind
    }

    private var healthPreferences: HealthPreferences {
        HealthPreferences(isEnabled: healthEnabled, kind: healthKind)
    }

    /// Turning on asks for permission first; it stays off if Health isn't
    /// available or the person doesn't allow saving workouts.
    public func setHealthEnabled(_ enabled: Bool) async {
        healthMessage = nil
        defer { healthPreferences.save(to: defaults) }
        guard enabled else {
            healthEnabled = false
            return
        }
        guard workoutStore.isAvailable else {
            healthEnabled = false
            healthMessage = "Apple Health isn't available on this device."
            return
        }
        do {
            healthEnabled = try await workoutStore.requestAccess()
            if !healthEnabled {
                healthMessage = "Mend isn't allowed to save workouts. You can allow it in Settings → Privacy & Security → Health → Mend."
            }
        } catch {
            logger.error("Health authorization failed: \(String(describing: error), privacy: .public)")
            healthEnabled = false
            healthMessage = "Couldn't connect to Apple Health. Try again."
        }
    }

    public func applyReminder() async {
        if reminderEnabled {
            do {
                guard try await scheduler.requestAuthorization() else { reminderEnabled = false; return }
                let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                try await scheduler.schedule(at: comps)
            } catch {
                reminderEnabled = false
            }
        } else {
            scheduler.cancel()
        }
    }
}
