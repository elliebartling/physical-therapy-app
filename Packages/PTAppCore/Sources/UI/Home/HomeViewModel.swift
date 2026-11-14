import Foundation
import Observation
import DataKit
import HistoryKit

@MainActor
@Observable
public final class HomeViewModel {
    public struct ExerciseRow: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let number: String
        public let name: String
        public let prescription: String
        public let art: ArtChoice
    }

    private let routineRepo: RoutineRepository
    private let sessionRepo: SessionRepository
    private let today: Date

    public private(set) var hasRoutine = false
    public private(set) var routineName = ""
    public private(set) var rows: [ExerciseRow] = []
    public private(set) var estimatedMinutes = 0
    public private(set) var streak = 0
    public private(set) var week = WeekStrip(days: [])

    public init(routineRepo: RoutineRepository, sessionRepo: SessionRepository, today: Date = .now) {
        self.routineRepo = routineRepo
        self.sessionRepo = sessionRepo
        self.today = today
    }

    public var isDoneToday: Bool { week.isTodayCompleted }

    /// The big statement at the top of Today. Kind, never guilt-tripping.
    public var headline: String {
        if isDoneToday { return "Done for today." }
        switch week.completedCount {
        case 0: return "Ready when you are."
        case 1: return "1 session this week."
        case let n: return "\(n) sessions this week."
        }
    }

    /// A log for a session done away from the app, or nil when there's no routine.
    public func logSession(on date: Date) -> LogSessionViewModel? {
        guard let routine = try? routineRepo.fetchActive() else { return nil }
        return LogSessionViewModel(routine: routine, sessionRepo: sessionRepo, date: date, now: today)
    }

    public func refresh() async {
        let routine = try? routineRepo.fetchActive()
        hasRoutine = routine != nil
        routineName = routine?.name ?? ""

        let exercises = routine?.orderedExercises ?? []
        rows = exercises.enumerated().map { index, exercise in
            ExerciseRow(
                id: exercise.id,
                number: String(format: "%02d", index + 1),
                name: exercise.name,
                prescription: Prescription.text(target: exercise.target, side: exercise.side),
                art: exercise.art
            )
        }
        estimatedMinutes = SessionEstimate.minutes(for: exercises)

        let sessions = (try? sessionRepo.fetchAll()) ?? []
        streak = StreakCalculator.currentStreak(in: sessions, today: today)
        week = WeekStrip.forWeek(containing: today, sessions: sessions)
    }
}
