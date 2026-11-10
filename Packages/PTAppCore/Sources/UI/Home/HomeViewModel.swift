import Foundation
import Observation
import DataKit
import HistoryKit

@MainActor
@Observable
public final class HomeViewModel {
    private let routineRepo: RoutineRepository
    private let sessionRepo: SessionRepository
    private let today: Date

    public private(set) var hasRoutine = false
    public private(set) var streak = 0
    public private(set) var heatmap = HeatmapMatrix(year: 0, month: 0, daysInMonth: 0, completedDayNumbers: [])

    public init(routineRepo: RoutineRepository, sessionRepo: SessionRepository, today: Date = .now) {
        self.routineRepo = routineRepo
        self.sessionRepo = sessionRepo
        self.today = today
    }

    public func refresh() async {
        hasRoutine = (try? routineRepo.fetchActive()) != nil
        let sessions = (try? sessionRepo.fetchAll()) ?? []
        streak = StreakCalculator.currentStreak(in: sessions, today: today)
        heatmap = HeatmapMatrix.forMonth(containing: today, sessions: sessions)
    }
}
