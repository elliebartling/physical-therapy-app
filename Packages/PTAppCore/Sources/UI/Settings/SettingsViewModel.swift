import Foundation
import Observation
import os
import DataKit

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
    /// Reading other workouts from Apple Health.
    public private(set) var readsWorkouts: Bool
    /// Shown under the other-workouts switch when turning it on didn't work.
    public private(set) var readMessage: String?
    /// Other workouts and what each kind covers.
    public let otherWorkouts: OtherWorkoutsSource
    /// The current routine's exercises, for saying what a workout covers.
    public var coverableExercises: [CoverableExercise] {
        CoverableExercise.all(in: try? routineRepo?.fetchActive())
    }

    /// Shown under the app icon picker when switching icons failed.
    public private(set) var appIconMessage: String?

    private let scheduler = NotificationScheduler()
    private let workoutStore: any WorkoutStore
    private let workoutReader: any WorkoutReader
    private let defaults: UserDefaults
    private let appIcons: AppIconController
    private let routineRepo: RoutineRepository?

    public init(workoutStore: any WorkoutStore = HealthKitWorkoutStore(),
                workoutReader: any WorkoutReader = HealthKitWorkoutReader(),
                defaults: UserDefaults = .standard,
                appIcons: AppIconController = AppIconController(),
                routineRepo: RoutineRepository? = nil) {
        self.workoutStore = workoutStore
        self.workoutReader = workoutReader
        self.defaults = defaults
        self.appIcons = appIcons
        self.routineRepo = routineRepo
        self.otherWorkouts = OtherWorkoutsSource(reader: workoutReader, defaults: defaults)
        let saved = HealthPreferences.load(from: defaults)
        self.healthEnabled = saved.isEnabled
        self.healthKind = saved.kind
        self.readsWorkouts = saved.readsWorkouts
    }

    private var healthPreferences: HealthPreferences {
        HealthPreferences(isEnabled: healthEnabled, kind: healthKind, readsWorkouts: readsWorkouts)
    }

    /// Turning on asks Health for permission to read workouts. Health never says whether
    /// reading was allowed, so it stays on unless the request itself fails.
    public func setReadsWorkouts(_ enabled: Bool) async {
        readMessage = nil
        defer { healthPreferences.save(to: defaults) }
        guard enabled else {
            readsWorkouts = false
            return
        }
        guard workoutReader.isAvailable else {
            readsWorkouts = false
            readMessage = "Apple Health isn't available on this device."
            return
        }
        do {
            try await workoutReader.requestReadAccess()
            readsWorkouts = true
        } catch {
            logger.error("Health read authorization failed: \(String(describing: error), privacy: .public)")
            readsWorkouts = false
            readMessage = "Couldn't connect to Apple Health. Try again."
        }
    }

    /// Puts the home-screen icon in step with the chosen design and accent.
    public func applyAppIcon(style: AppIconStyle, accent: AccentChoice, matchesAccent: Bool) async {
        appIconMessage = await appIcons.apply(style: style, accent: accent, matchesAccent: matchesAccent)
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
