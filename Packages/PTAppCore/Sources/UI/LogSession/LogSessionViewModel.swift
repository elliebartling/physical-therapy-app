import Foundation
import Observation
import DataKit
import os

private let logger = Logger(subsystem: "PTAppCore", category: "log-session")

/// Logs a session done away from the app, on today or an earlier day.
///
/// Every exercise starts checked. A session with every exercise done counts as
/// complete, like a guided one; otherwise it's kept as partial, like ending a
/// guided session early.
@MainActor
@Observable
public final class LogSessionViewModel {
    public struct Item: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let prescription: String
        public var isDone: Bool
    }

    public var date: Date
    public var items: [Item]
    public private(set) var errorMessage: String?

    /// The latest day that can be logged: today.
    public let latestDate: Date

    private let routineID: UUID
    private let exercises: [Exercise]
    private let sessionRepo: SessionRepository
    private let health: HealthRecorder?
    private let calendar: Calendar

    public init(routine: Routine, sessionRepo: SessionRepository, date: Date,
                now: Date = .now, calendar: Calendar = .current,
                health: HealthRecorder? = HealthRecorder()) {
        self.routineID = routine.id
        self.exercises = routine.orderedExercises
        self.sessionRepo = sessionRepo
        self.health = health
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

    /// Returns whether the session was saved.
    @discardableResult
    public func save() -> Bool {
        guard canSave else { return false }
        let loggedAt = timestamp(for: date)
        let records = items.map { item in
            ExerciseRecord(exerciseID: item.id,
                           status: item.isDone ? .completed : .skipped,
                           startedAt: loggedAt,
                           completedAt: item.isDone ? loggedAt : nil)
        }
        let session = SessionRecord(routineID: routineID,
                                    startedAt: loggedAt,
                                    completedAt: isEveryExerciseDone ? loggedAt : nil,
                                    exerciseRecords: records)
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
    /// length for the exercises that were done, ending at the logged time.
    /// The estimate is worked out now, so the save never touches the routine's
    /// models after this view model is gone.
    private func saveToHealth(endingAt end: Date) {
        guard let health else { return }
        let done = Set(items.filter(\.isDone).map(\.id))
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
