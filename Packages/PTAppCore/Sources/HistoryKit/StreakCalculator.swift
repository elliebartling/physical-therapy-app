import Foundation
import DataKit

public enum StreakCalculator {
    /// Current consecutive-day streak counted from the most recent completed day
    /// (today or yesterday) backwards.
    public static func currentStreak(
        in sessions: [SessionRecord],
        today: Date,
        calendar: Calendar = .current
    ) -> Int {
        let completedDays: Set<Date> = Set(
            sessions
                .compactMap(\.completedAt)
                .map { calendar.startOfDay(for: $0) }
        )
        guard !completedDays.isEmpty else { return 0 }

        let todayStart = calendar.startOfDay(for: today)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!

        var cursor: Date
        if completedDays.contains(todayStart) {
            cursor = todayStart
        } else if completedDays.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var streak = 0
        while completedDays.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }
}
