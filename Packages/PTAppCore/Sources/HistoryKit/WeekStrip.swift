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
        /// A session was started or logged but not finished, and none was completed.
        public let isPartial: Bool
        /// Another workout that day counts toward the goal and streak.
        public let countsOtherWorkout: Bool
        public var id: Date { date }

        public init(date: Date, isCompleted: Bool, isToday: Bool, otherWorkout: String? = nil,
                    isPartial: Bool = false, countsOtherWorkout: Bool = false) {
            self.date = date
            self.isCompleted = isCompleted
            self.isToday = isToday
            self.otherWorkout = otherWorkout
            self.isPartial = isPartial
            self.countsOtherWorkout = countsOtherWorkout
        }

        /// A completed PT session, or another workout that counts.
        public var isActive: Bool { isCompleted || countsOtherWorkout }
    }

    public let days: [Day]

    public init(days: [Day]) { self.days = days }

    public var completedCount: Int { days.filter(\.isCompleted).count }
    /// Days with a completed PT session or another workout that counts.
    public var activeCount: Int { days.filter(\.isActive).count }

    public var isTodayCompleted: Bool { days.first(where: \.isToday)?.isCompleted ?? false }

    public static func forWeek(
        containing date: Date,
        sessions: [SessionRecord],
        otherWorkouts: [OtherWorkout] = [],
        countingOtherWorkouts: Bool = false,
        calendar: Calendar = .current
    ) -> WeekStrip {
        let today = calendar.startOfDay(for: date)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return WeekStrip(days: [])
        }
        let completedDays = Set(sessions.compactMap(\.completedAt).map { calendar.startOfDay(for: $0) })
        let triedDays = Set(sessions.filter { $0.completedAt == nil }.map { calendar.startOfDay(for: $0.startedAt) })
        let countedDays = countingOtherWorkouts
            ? OtherWorkoutStats.countingDays(of: otherWorkouts, calendar: calendar) : []
        let days = (0..<7).compactMap { offset -> Day? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else { return nil }
            // The longest workout that day gives the tag.
            let other = otherWorkouts
                .filter { calendar.startOfDay(for: $0.start) == day }
                .max { $0.minutes < $1.minutes }
            let isCompleted = completedDays.contains(day)
            return Day(date: day, isCompleted: isCompleted, isToday: day == today,
                       otherWorkout: other?.activity.tag,
                       isPartial: !isCompleted && triedDays.contains(day),
                       countsOtherWorkout: countedDays.contains(day))
        }
        return WeekStrip(days: days)
    }
}
