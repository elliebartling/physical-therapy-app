import Foundation

public struct WeekStat: Identifiable, Sendable {
    public let weekStart: Date
    public let sessions: Int
    public let target: Int

    public var id: Date { weekStart }
    public var metTarget: Bool { sessions >= target }
}

/// Pure functions over session dates. A "session day" counts once no matter
/// how many sessions happened that day — compliance is about showing up.
public enum ComplianceEngine {
    public static func weekStats(
        sessionDates: [Date],
        target: Int,
        weeks: Int = 8,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [WeekStat] {
        guard weeks > 0,
              let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return []
        }
        let sessionDays = Set(sessionDates.map { calendar.startOfDay(for: $0) })
        return (0..<weeks).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeekStart),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else {
                return nil
            }
            let count = sessionDays.filter { $0 >= start && $0 < end }.count
            return WeekStat(weekStart: start, sessions: count, target: target)
        }
    }

    public static func currentWeekCount(
        sessionDates: [Date],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Int {
        weekStats(sessionDates: sessionDates, target: 1, weeks: 1, calendar: calendar, now: now)
            .last?.sessions ?? 0
    }

    /// Consecutive weeks that met the target. The in-progress week counts if
    /// already met, and doesn't break the streak if not yet.
    public static func weekStreak(
        sessionDates: [Date],
        target: Int,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Int {
        var stats = weekStats(sessionDates: sessionDates, target: target, weeks: 104, calendar: calendar, now: now)
        guard !stats.isEmpty else { return 0 }
        var streak = 0
        let current = stats.removeLast()
        if current.metTarget {
            streak += 1
        }
        for stat in stats.reversed() {
            if stat.metTarget {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    /// Consecutive days with at least one session, anchored at today
    /// (or yesterday, so the streak survives until the day is truly missed).
    public static func dayStreak(
        sessionDates: [Date],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Int {
        let sessionDays = Set(sessionDates.map { calendar.startOfDay(for: $0) })
        var anchor = calendar.startOfDay(for: now)
        if !sessionDays.contains(anchor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: anchor),
                  sessionDays.contains(yesterday) else {
                return 0
            }
            anchor = yesterday
        }
        var streak = 0
        var day = anchor
        while sessionDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }
}
