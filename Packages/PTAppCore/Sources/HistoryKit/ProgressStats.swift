import Foundation
import DataKit

/// Days with a completed session in one calendar week.
public struct WeekCount: Equatable, Sendable, Identifiable {
    public let weekStart: Date
    public let days: Int
    public var id: Date { weekStart }

    public init(weekStart: Date, days: Int) {
        self.weekStart = weekStart
        self.days = days
    }
}

/// How often one exercise was done or skipped, across every session.
public struct ExerciseStats: Equatable, Sendable {
    public var completed: Int
    public var skipped: Int
    public var lastDone: Date?

    public init(completed: Int = 0, skipped: Int = 0, lastDone: Date? = nil) {
        self.completed = completed
        self.skipped = skipped
        self.lastDone = lastDone
    }

    /// Share of the times it came up that it was done; nil if it never came up.
    public var completionRate: Double? {
        let total = completed + skipped
        return total == 0 ? nil : Double(completed) / Double(total)
    }
}

/// The numbers behind the Progress screen. Pure functions over session records.
public enum ProgressStats {
    /// The last `weeks` calendar weeks, oldest first, ending with the week
    /// containing `today`. Counts distinct days with a completed session, the
    /// same rule as the week strip and the streak.
    public static func weeklyDays(
        in sessions: [SessionRecord],
        weeks: Int,
        today: Date,
        calendar: Calendar = .current
    ) -> [WeekCount] {
        guard weeks > 0, let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today) else { return [] }
        let completedDays = Set(sessions.compactMap(\.completedAt).map { calendar.startOfDay(for: $0) })
        return (0..<weeks).reversed().compactMap { back -> WeekCount? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek.start),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
            let days = completedDays.filter { $0 >= start && $0 < end }.count
            return WeekCount(weekStart: start, days: days)
        }
    }

    /// Every exercise that appears in a session, keyed by exercise id.
    public static func exerciseStats(in sessions: [SessionRecord]) -> [UUID: ExerciseStats] {
        var stats: [UUID: ExerciseStats] = [:]
        for session in sessions {
            for record in session.exerciseRecords {
                var entry = stats[record.exerciseID, default: ExerciseStats()]
                switch record.status {
                case .completed:
                    entry.completed += 1
                    let doneAt = record.completedAt ?? record.startedAt
                    if entry.lastDone.map({ doneAt > $0 }) ?? true { entry.lastDone = doneAt }
                case .skipped, .partial:
                    entry.skipped += 1
                }
                stats[record.exerciseID] = entry
            }
        }
        return stats
    }

    /// Distinct days with a completed session.
    public static func completedDayCount(in sessions: [SessionRecord], calendar: Calendar = .current) -> Int {
        Set(sessions.compactMap(\.completedAt).map { calendar.startOfDay(for: $0) }).count
    }
}
