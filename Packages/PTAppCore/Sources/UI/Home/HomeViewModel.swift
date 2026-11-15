import Foundation
import Observation
import DataKit
import HistoryKit
import os

private let logger = Logger(subsystem: "PTAppCore", category: "home")

@MainActor
@Observable
public final class HomeViewModel {
    public struct ExerciseRow: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let number: String
        public let name: String
        public let prescription: String
        public let art: ArtChoice
        /// The other workout that stood in for it today, e.g. "Yoga".
        public var coveredBy: String? = nil
    }

    /// A workout from Apple Health that covers some of today's exercises, waiting for a yes.
    public struct CoverageOffer: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let workoutName: String
        public let minutes: Int
        public let end: Date
        public let exercises: [Covered]

        public struct Covered: Equatable, Sendable {
            public let id: UUID
            public let name: String
        }
    }

    private let routineRepo: RoutineRepository
    private let sessionRepo: SessionRepository
    private let otherWorkouts: OtherWorkoutsSource?
    /// Fixed in tests; otherwise read fresh, since Today stays alive across midnight.
    private let fixedToday: Date?
    private var today: Date { fixedToday ?? .now }
    private let calendar: Calendar

    public private(set) var hasRoutine = false
    public private(set) var routineName = ""
    public private(set) var rows: [ExerciseRow] = []
    public private(set) var estimatedMinutes = 0
    public private(set) var streak = 0
    public private(set) var week = WeekStrip(days: [])
    public private(set) var offers: [CoverageOffer] = []
    public private(set) var errorMessage: String?
    /// Today's workouts from Health, kept for counting an offer.
    private var todaysWorkouts: [OtherWorkout] = []

    public init(routineRepo: RoutineRepository, sessionRepo: SessionRepository,
                otherWorkouts: OtherWorkoutsSource? = OtherWorkoutsSource(),
                today: Date? = nil, calendar: Calendar = .current) {
        self.routineRepo = routineRepo
        self.sessionRepo = sessionRepo
        self.otherWorkouts = otherWorkouts
        self.fixedToday = today
        self.calendar = calendar
    }

    public var isDoneToday: Bool { week.isTodayCompleted }

    /// Exercises still to do today: not done, and not covered by another workout.
    public var remainingCount: Int { rows.filter { $0.coveredBy == nil }.count }

    /// The big statement at the top of Today. Kind, never guilt-tripping.
    public var headline: String {
        if isDoneToday { return "Done for today." }
        if week.activeCount > week.completedCount {
            return week.activeCount == 1 ? "1 active day this week." : "\(week.activeCount) active days this week."
        }
        switch week.completedCount {
        case 0: return "Ready when you are."
        case 1: return "1 session this week."
        case let n: return "\(n) sessions this week."
        }
    }

    /// A log for a session done away from the app, or nil when there's no routine.
    public func logSession(on date: Date) -> LogSessionViewModel? {
        guard let routine = try? routineRepo.fetchActive() else { return nil }
        return LogSessionViewModel(routine: routine, sessionRepo: sessionRepo, date: date, now: today,
                                   calendar: calendar, otherWorkouts: otherWorkouts)
    }

    public func refresh() async {
        let routine = try? routineRepo.fetchActive()
        hasRoutine = routine != nil
        routineName = routine?.name ?? ""
        let exercises = routine?.orderedExercises ?? []

        // This week's workouts, or a year's when they count toward the streak.
        var recentWorkouts: [OtherWorkout] = []
        let counting = otherWorkouts?.countsTowardGoal ?? false
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? calendar.startOfDay(for: today)
        if let otherWorkouts, otherWorkouts.isOn {
            let from = counting
                ? calendar.date(byAdding: .day, value: -ActivityStreak.lookbackDays, to: today) ?? weekStart
                : weekStart
            recentWorkouts = await otherWorkouts.workouts(from: min(from, weekStart), to: today)
        }
        let weekWorkouts = recentWorkouts.filter { $0.start >= weekStart }
        let todayStart = calendar.startOfDay(for: today)
        todaysWorkouts = weekWorkouts.filter { calendar.startOfDay(for: $0.start) == todayStart }

        var sessions = (try? sessionRepo.fetchAll()) ?? []
        if let routine {
            // Workouts set to count without asking count now.
            var attempted: Set<UUID> = []
            while let offer = pendingOffers(routine: routine, sessions: sessions)
                .first(where: { !asksFirst($0) && !attempted.contains($0.id) }) {
                attempted.insert(offer.id)
                record(offer, routine: routine, sessions: sessions)
                sessions = (try? sessionRepo.fetchAll()) ?? sessions
            }
            offers = pendingOffers(routine: routine, sessions: sessions)
        } else {
            offers = []
        }

        let covered = OtherWorkoutStats.coveredExercises(on: today, in: sessions, calendar: calendar)
        rows = exercises.enumerated().map { index, exercise in
            ExerciseRow(
                id: exercise.id,
                number: String(format: "%02d", index + 1),
                name: exercise.name,
                prescription: Prescription.text(target: exercise.target, side: exercise.side),
                art: exercise.art,
                coveredBy: covered[exercise.id]
            )
        }
        estimatedMinutes = SessionEstimate.minutes(for: exercises.filter { covered[$0.id] == nil })
        streak = StreakCalculator.currentStreak(
            in: sessions, today: today, calendar: calendar,
            extraDays: counting ? OtherWorkoutStats.countingDays(of: recentWorkouts, calendar: calendar) : []
        )
        week = WeekStrip.forWeek(containing: today, sessions: sessions, otherWorkouts: weekWorkouts,
                                 countingOtherWorkouts: counting, calendar: calendar)
    }

    /// Counts the offered workout for the exercises it covers.
    public func count(_ offer: CoverageOffer) async {
        guard let routine = try? routineRepo.fetchActive() else { return }
        let sessions = (try? sessionRepo.fetchAll()) ?? []
        record(offer, routine: routine, sessions: sessions)
        await refresh()
    }

    /// Doesn't count it, and stops offering it.
    public func dismiss(_ offer: CoverageOffer) {
        otherWorkouts?.dismiss(offer.id)
        offers.removeAll { $0.id == offer.id }
    }

    public func dismissError() { errorMessage = nil }

    // MARK: Coverage

    private func asksFirst(_ offer: CoverageOffer) -> Bool {
        guard let workout = todaysWorkouts.first(where: { $0.id == offer.id }) else { return true }
        return otherWorkouts?.rule(for: workout.activity.id)?.asksFirst ?? true
    }

    /// Today's workouts that a rule says cover exercises not yet done or covered today,
    /// and that haven't been counted or turned down.
    private func pendingOffers(routine: Routine, sessions: [SessionRecord]) -> [CoverageOffer] {
        guard let otherWorkouts else { return [] }
        let counted = Set(sessions.compactMap(\.coveringWorkoutID))
        let done = OtherWorkoutStats.doneExercises(on: today, in: sessions, calendar: calendar)
        let covered = OtherWorkoutStats.coveredExercises(on: today, in: sessions, calendar: calendar)
        return todaysWorkouts.compactMap { workout -> CoverageOffer? in
            guard !counted.contains(workout.id), !otherWorkouts.isDismissed(workout.id),
                  let rule = otherWorkouts.rule(for: workout.activity.id), rule.applies(to: workout) else { return nil }
            let exercises = routine.orderedExercises.filter {
                rule.exerciseLineages.contains($0.lineageID) && !done.contains($0.id) && covered[$0.id] == nil
            }
            guard !exercises.isEmpty else { return nil }
            return CoverageOffer(id: workout.id, workoutName: workout.activity.name, minutes: workout.minutes,
                                 end: workout.end,
                                 exercises: exercises.map { .init(id: $0.id, name: $0.name) })
        }
    }

    /// Saves the covered exercises as their own session, stamped when the workout ended.
    /// The session is complete when, with what's already done today, nothing is left.
    private func record(_ offer: CoverageOffer, routine: Routine, sessions: [SessionRecord]) {
        let done = OtherWorkoutStats.doneExercises(on: today, in: sessions, calendar: calendar)
        let finished = Set(routine.exercises.map(\.id))
            .isSubset(of: done.union(offer.exercises.map(\.id)))
        let records = offer.exercises.map { exercise in
            let record = ExerciseRecord(exerciseID: exercise.id, status: .completed,
                                        startedAt: offer.end, completedAt: offer.end)
            record.coveredBy = offer.workoutName
            return record
        }
        let session = SessionRecord(routineID: routine.id, startedAt: offer.end,
                                    completedAt: finished ? offer.end : nil, exerciseRecords: records)
        session.coveringWorkoutID = offer.id
        do {
            try sessionRepo.insert(session)
        } catch {
            logger.error("Counting a workout failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't count that workout. Try again."
        }
    }
}
