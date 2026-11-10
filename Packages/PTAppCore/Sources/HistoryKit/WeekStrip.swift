import Foundation
import DataKit

/// The seven days of the calendar week containing a date, marking which had a completed session.
public struct WeekStrip: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public let date: Date
        public let isCompleted: Bool
        public let isToday: Bool
        public var id: Date { date }

        public init(date: Date, isCompleted: Bool, isToday: Bool) {
            self.date = date
            self.isCompleted = isCompleted
            self.isToday = isToday
        }
    }

    public let days: [Day]

    public init(days: [Day]) { self.days = days }

    public var completedCount: Int { days.filter(\.isCompleted).count }

    public var isTodayCompleted: Bool { days.first(where: \.isToday)?.isCompleted ?? false }

    public static func forWeek(
        containing date: Date,
        sessions: [SessionRecord],
        calendar: Calendar = .current
    ) -> WeekStrip {
        let today = calendar.startOfDay(for: date)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return WeekStrip(days: [])
        }
        let completedDays = Set(sessions.compactMap(\.completedAt).map { calendar.startOfDay(for: $0) })
        let days = (0..<7).compactMap { offset -> Day? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else { return nil }
            return Day(date: day, isCompleted: completedDays.contains(day), isToday: day == today)
        }
        return WeekStrip(days: days)
    }
}
