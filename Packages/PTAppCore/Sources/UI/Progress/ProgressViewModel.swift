import Foundation
import Observation
import DataKit
import HistoryKit
import os

private let logger = Logger(subsystem: "PTAppCore", category: "progress")

/// Everything the Progress tab shows: consistency, each exercise, and every session.
@MainActor
@Observable
public final class ProgressViewModel {
    public struct ExerciseRow: Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public let prescription: String
        public let stats: ExerciseStats
        /// The most recent rating it was given, if any.
        public let lastRating: ExerciseRating?
    }

    public struct SessionItem: Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public let isDone: Bool
        public let rating: ExerciseRating?
    }

    public struct SessionRow: Identifiable, Equatable {
        public let id: UUID
        public let date: Date
        public let isComplete: Bool
        /// Timed in the app; nil for a session logged afterwards.
        public let minutes: Int?
        public let items: [SessionItem]
        public let painLevel: Int?
        public let note: String?
        public var doneCount: Int { items.filter(\.isDone).count }
    }

    public struct Month: Identifiable, Equatable {
        public let id: Date
        public let title: String
        public let sessions: [SessionRow]
    }

    /// One time an exercise came up in a session.
    public struct ExerciseEntry: Identifiable, Equatable {
        public let id: UUID
        public let date: Date
        public let isDone: Bool
        public let rating: ExerciseRating?
    }

    public static let weeksShown = 8

    public private(set) var weeks: [WeekCount] = []
    public private(set) var activeDays = 0
    public private(set) var streak = 0
    public private(set) var exercises: [ExerciseRow] = []
    public private(set) var months: [Month] = []
    public private(set) var errorMessage: String?

    public var hasSessions: Bool { !months.isEmpty }

    private let routineRepo: RoutineRepository
    private let sessionRepo: SessionRepository
    private let today: Date
    private let calendar: Calendar
    private var sessions: [SessionRecord] = []
    private var names: [UUID: String] = [:]
    private var order: [UUID: Int] = [:]
    /// Exercise id → lineage, so one exercise's history spans routine phases.
    private var lineage: [UUID: UUID] = [:]

    public init(routineRepo: RoutineRepository, sessionRepo: SessionRepository,
                today: Date = .now, calendar: Calendar = .current) {
        self.routineRepo = routineRepo
        self.sessionRepo = sessionRepo
        self.today = today
        self.calendar = calendar
    }

    public func refresh() {
        do {
            sessions = try sessionRepo.fetchAll()
            let routines = try routineRepo.fetchAll()
            errorMessage = nil
            build(routines: routines)
        } catch {
            logger.error("Loading progress failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't load your history. Try again."
        }
    }

    /// Every time the exercise came up, in this phase or earlier ones, newest first.
    public func entries(forExercise id: UUID) -> [ExerciseEntry] {
        let group = lineage[id] ?? id
        return sessions
            .flatMap(\.exerciseRecords)
            .filter { (lineage[$0.exerciseID] ?? $0.exerciseID) == group }
            .map { ExerciseEntry(id: $0.id, date: $0.completedAt ?? $0.startedAt,
                                 isDone: $0.status == .completed, rating: $0.rating) }
            .sorted { $0.date > $1.date }
    }

    public func exercise(id: UUID) -> ExerciseRow? { exercises.first { $0.id == id } }

    public func session(id: UUID) -> SessionRow? {
        months.lazy.flatMap(\.sessions).first { $0.id == id }
    }

    /// Deletes a session, e.g. one logged by mistake. Returns whether it worked.
    @discardableResult
    public func deleteSession(id: UUID) -> Bool {
        guard let record = sessions.first(where: { $0.id == id }) else { return false }
        do {
            try sessionRepo.delete(record)
            refresh()
            return true
        } catch {
            logger.error("Deleting a session failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't delete that session. Try again."
            return false
        }
    }

    public func dismissError() { errorMessage = nil }

    private func build(routines: [Routine]) {
        // Names come from every routine, so sessions from a replaced routine still read well.
        let allExercises = routines.flatMap(\.exercises)
        names = Dictionary(allExercises.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        order = Dictionary(allExercises.map { ($0.id, $0.order) }, uniquingKeysWith: { first, _ in first })
        lineage = Dictionary(allExercises.map { ($0.id, $0.lineageID) }, uniquingKeysWith: { first, _ in first })

        weeks = ProgressStats.weeklyDays(in: sessions, weeks: Self.weeksShown, today: today, calendar: calendar)
        activeDays = weeks.reduce(0) { $0 + $1.days }
        streak = StreakCalculator.currentStreak(in: sessions, today: today, calendar: calendar)

        let stats = ProgressStats.exerciseStats(in: sessions, groupedBy: { [lineage] in lineage[$0] ?? $0 })
        let active = routines.first(where: \.isActive)?.orderedExercises ?? []
        exercises = active.map { exercise in
            ExerciseRow(id: exercise.id,
                        name: exercise.name,
                        prescription: Prescription.text(target: exercise.target, side: exercise.side),
                        stats: stats[exercise.lineageID] ?? ExerciseStats(),
                        lastRating: entries(forExercise: exercise.id).first(where: { $0.rating != nil })?.rating)
        }

        let rows = sessions.sorted { $0.startedAt > $1.startedAt }.map(row(for:))
        let byMonth = Dictionary(grouping: rows) { row in
            calendar.dateInterval(of: .month, for: row.date)?.start ?? row.date
        }
        months = byMonth.keys.sorted(by: >).map { start in
            Month(id: start,
                  title: start.formatted(.dateTime.month(.wide).year()),
                  sessions: byMonth[start] ?? [])
        }
    }

    private func row(for session: SessionRecord) -> SessionRow {
        var minutes: Int?
        if let end = session.completedAt {
            let seconds = end.timeIntervalSince(session.startedAt)
            // A logged session has no timing: it starts and ends at the same moment.
            if seconds >= 30 { minutes = max(1, Int((seconds / 60).rounded())) }
        }
        let items = session.exerciseRecords
            .sorted {
                // A logged session stamps every exercise with the same time; fall back to routine order.
                ($0.startedAt, order[$0.exerciseID] ?? .max) < ($1.startedAt, order[$1.exerciseID] ?? .max)
            }
            .map { record in
                SessionItem(id: record.id,
                            name: names[record.exerciseID] ?? "Removed exercise",
                            isDone: record.status == .completed,
                            rating: record.rating)
            }
        return SessionRow(id: session.id, date: session.startedAt,
                          isComplete: session.isComplete, minutes: minutes, items: items,
                          painLevel: session.painLevel, note: session.note)
    }
}
