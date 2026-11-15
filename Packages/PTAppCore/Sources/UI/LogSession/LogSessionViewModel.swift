import Foundation
import Observation
import DataKit
import HistoryKit
import os

private let logger = Logger(subsystem: "PTAppCore", category: "log-session")

/// Logs a session done away from the app, on today or an earlier day.
///
/// Every exercise starts checked. A session with every exercise done counts as
/// complete, like a guided one; otherwise it's kept as partial, like ending a
/// guided session early. That day's other workouts from Apple Health can count
/// for the exercises they cover.
@MainActor
@Observable
public final class LogSessionViewModel {
    public struct Item: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let prescription: String
        public var isDone: Bool
        /// The other workout counted for it, e.g. "Yoga".
        public var coveredBy: String? = nil
    }

    /// A workout from Apple Health on the day being logged.
    public struct WorkoutOption: Identifiable, Equatable, Sendable {
        public let workout: OtherWorkout
        /// Exercises it's set to cover; empty until the person says what it covers.
        public var covers: [UUID]
        public var isCounted: Bool
        public var id: UUID { workout.id }
        public var name: String { workout.activity.name }
    }

    public var date: Date {
        didSet {
            if !calendar.isDate(date, inSameDayAs: oldValue) { clearCoverage() }
        }
    }
    public var items: [Item]
    public private(set) var workouts: [WorkoutOption] = []
    public private(set) var errorMessage: String?

    /// The latest day that can be logged: today.
    public let latestDate: Date

    private let routineID: UUID
    private let exercises: [Exercise]
    private let sessionRepo: SessionRepository
    private let health: HealthRecorder?
    /// Where other workouts and what they cover come from; nil when not offered.
    public let otherWorkouts: OtherWorkoutsSource?
    private let calendar: Calendar

    public init(routine: Routine, sessionRepo: SessionRepository, date: Date,
                now: Date = .now, calendar: Calendar = .current,
                health: HealthRecorder? = HealthRecorder(),
                otherWorkouts: OtherWorkoutsSource? = nil) {
        self.routineID = routine.id
        self.exercises = routine.orderedExercises
        self.sessionRepo = sessionRepo
        self.health = health
        self.otherWorkouts = otherWorkouts
        self.calendar = calendar
        self.latestDate = now
        self.date = min(date, now)
        self.items = routine.orderedExercises.map { exercise in
            Item(id: exercise.id,
                 name: exercise.name,
                 prescription: Prescription.text(target: exercise.target, side: exercise.side),
                 isDone: true)
        }
    }

    public var canSave: Bool { items.contains(where: \.isDone) }
    public var isEveryExerciseDone: Bool { items.allSatisfy(\.isDone) }

    /// The routine's exercises, for saying what a workout covers.
    public var coverableExercises: [CoverableExercise] {
        exercises.map { CoverableExercise(lineage: $0.lineageID, name: $0.name) }
    }

    /// Names of the exercises a workout covers, in routine order.
    public func coveredNames(for option: WorkoutOption) -> [String] {
        items.filter { option.covers.contains($0.id) }.map(\.name)
    }

    public func setDone(_ isDone: Bool, for itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].isDone = isDone
        if !isDone { items[index].coveredBy = nil }
    }

    // MARK: Other workouts

    /// Reads the day's workouts from Apple Health, leaving out any already counted.
    /// Ones set to cover exercises start counted.
    public func loadWorkouts() async {
        guard let otherWorkouts, otherWorkouts.isOn else {
            workouts = []
            return
        }
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let found = await otherWorkouts.workouts(from: start, to: min(end, latestDate))
        let counted = Set(((try? sessionRepo.fetchAll()) ?? []).compactMap(\.coveringWorkoutID))
        clearCoverage()
        workouts = found
            .filter { !counted.contains($0.id) }
            .sorted { $0.start < $1.start }
            .map { workout in
                let rule = otherWorkouts.rule(for: workout.activity.id)
                return WorkoutOption(workout: workout, covers: covers(of: rule),
                                     isCounted: rule?.applies(to: workout) ?? false)
            }
        applyCoverage()
    }

    /// Picks up what each kind of workout covers after the person changes it.
    /// A workout that now covers something, and didn't before, starts counted.
    public func refreshRules() {
        guard let otherWorkouts else { return }
        for index in workouts.indices {
            let covers = covers(of: otherWorkouts.rule(for: workouts[index].workout.activity.id))
            if workouts[index].covers.isEmpty, !covers.isEmpty { workouts[index].isCounted = true }
            workouts[index].covers = covers
            if covers.isEmpty { workouts[index].isCounted = false }
        }
        applyCoverage()
    }

    public func setCounted(_ isCounted: Bool, for workoutID: UUID) {
        guard let index = workouts.firstIndex(where: { $0.id == workoutID }) else { return }
        workouts[index].isCounted = isCounted && !workouts[index].covers.isEmpty
        applyCoverage()
    }

    private func covers(of rule: CoverageRule?) -> [UUID] {
        guard let rule else { return [] }
        return exercises.filter { rule.exerciseLineages.contains($0.lineageID) }.map(\.id)
    }

    /// Marks what counted workouts cover as done and covered; the first workout wins.
    private func applyCoverage() {
        var coveredBy: [UUID: String] = [:]
        for option in workouts where option.isCounted {
            for id in option.covers where coveredBy[id] == nil { coveredBy[id] = option.name }
        }
        for index in items.indices {
            if let name = coveredBy[items[index].id] {
                items[index].coveredBy = name
                items[index].isDone = true
            } else {
                items[index].coveredBy = nil
            }
        }
    }

    private func clearCoverage() {
        workouts = []
        for index in items.indices { items[index].coveredBy = nil }
    }

    // MARK: Saving

    /// Returns whether the session was saved.
    @discardableResult
    public func save() -> Bool {
        guard canSave else { return false }
        let loggedAt = timestamp(for: date)
        let records = items.map { item in
            let record = ExerciseRecord(exerciseID: item.id,
                                        status: item.isDone ? .completed : .skipped,
                                        startedAt: loggedAt,
                                        completedAt: item.isDone ? loggedAt : nil)
            record.coveredBy = item.isDone ? item.coveredBy : nil
            return record
        }
        let session = SessionRecord(routineID: routineID,
                                    startedAt: loggedAt,
                                    completedAt: isEveryExerciseDone ? loggedAt : nil,
                                    exerciseRecords: records)
        let coveredIDs = Set(items.filter { $0.isDone && $0.coveredBy != nil }.map(\.id))
        session.coveringWorkoutID = workouts.first { $0.isCounted && !coveredIDs.isDisjoint(with: $0.covers) }?.id
        do {
            try sessionRepo.insert(session)
            errorMessage = nil
            saveToHealth(endingAt: loggedAt)
            return true
        } catch {
            logger.error("Logging a session failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't save this session. Try again."
            return false
        }
    }

    public func dismissError() { errorMessage = nil }

    /// The Apple Health save started by the last `save()`, if any.
    @ObservationIgnored private(set) var healthSave: Task<Void, Never>?

    /// A logged session has no timing, so Health gets the routine's estimated
    /// length for the exercises that were done in Mend, ending at the logged time.
    /// Covered exercises are left out: their workout is already in Health.
    /// The estimate is worked out now, so the save never touches the routine's
    /// models after this view model is gone.
    private func saveToHealth(endingAt end: Date) {
        guard let health else { return }
        let done = Set(items.filter { $0.isDone && $0.coveredBy == nil }.map(\.id))
        guard !done.isEmpty else { return }
        let minutes = max(1, SessionEstimate.minutes(for: exercises.filter { done.contains($0.id) }))
        let start = end.addingTimeInterval(-Double(minutes) * 60)
        healthSave = Task { await health.record(start: start, end: end, wasLoggedLater: true) }
    }

    /// Today keeps the current time. An earlier day is logged at midday, so the
    /// session can't slip into a neighbouring day.
    private func timestamp(for day: Date) -> Date {
        if calendar.isDate(day, inSameDayAs: latestDate) { return latestDate }
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .hour, value: 12, to: start) ?? start
    }
}
