import Foundation
import DataKit

/// The seven days of the calendar week containing a date, marking which had a completed session.
public struct WeekStrip: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public let date: Date
        public let isCompleted: Bool
        public let isToday: Bool
        /// The tag of a workout from outside Mend that day, e.g. "RUN".
        public let otherWorkout: String?
        public var id: Date { date }

        public init(date: Date, isCompleted: Bool, isToday: Bool, otherWorkout: String? = nil) {
            self.date = date
            self.isCompleted = isCompleted
            self.isToday = isToday
            self.otherWorkout = otherWorkout
        }
    }

    public let days: [Day]

    public init(days: [Day]) { self.days = days }

    public var completedCount: Int { days.filter(\.isCompleted).count }

    public var isTodayCompleted: Bool { days.first(where: \.isToday)?.isCompleted ?? false }

    public static func forWeek(
        containing date: Date,
        sessions: [SessionRecord],
        otherWorkouts: [OtherWorkout] = [],
        calendar: Calendar = .current
    ) -> WeekStrip {
        let today = calendar.startOfDay(for: date)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return WeekStrip(days: [])
        }
        let completedDays = Set(sessions.compactMap(\.completedAt).map { calendar.startOfDay(for: $0) })
        let days = (0..<7).compactMap { offset -> Day? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else { return nil }
            // The longest workout that day gives the tag.
            let other = otherWorkouts
                .filter { calendar.startOfDay(for: $0.start) == day }
                .max { $0.minutes < $1.minutes }
            return Day(date: day, isCompleted: completedDays.contains(day), isToday: day == today,
                       otherWorkout: other?.activity.tag)
        }
        return WeekStrip(days: days)
    }
}
