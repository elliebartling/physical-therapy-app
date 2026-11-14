import Foundation
import DataKit

/// How far back the Progress screen looks.
public enum ProgressRange: String, CaseIterable, Identifiable, Sendable {
    case fourWeeks, threeMonths, all

    public var id: Self { self }

    public var title: String {
        switch self {
        case .fourWeeks: "4W"
        case .threeMonths: "3M"
        case .all: "All"
        }
    }

    public var spokenTitle: String {
        switch self {
        case .fourWeeks: "4 weeks"
        case .threeMonths: "3 months"
        case .all: "All time"
        }
    }

    /// Calendar weeks covered, ending with the week containing `today`. `all` reaches
    /// back to the first session's week (at least 4 weeks, at most two years).
    public func weekCount(firstSession: Date?, today: Date, calendar: Calendar = .current) -> Int {
        switch self {
        case .fourWeeks: return 4
        case .threeMonths: return 13
        case .all:
            guard let firstSession,
                  let firstWeek = calendar.dateInterval(of: .weekOfYear, for: firstSession)?.start,
                  let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return 4 }
            let back = calendar.dateComponents([.weekOfYear], from: firstWeek, to: thisWeek).weekOfYear ?? 0
            return min(max(back + 1, 4), 104)
        }
    }
}

/// One day on the consistency heatmap.
public enum DayState: Equatable, Sendable {
    /// A completed session.
    case done
    /// A session was started or logged but not every exercise was done.
    case partial
    case rest
    /// Later this week.
    case future
}

/// One column of the heatmap: a calendar week, first weekday first.
public struct HeatmapWeek: Equatable, Sendable, Identifiable {
    public let weekStart: Date
    public let days: [DayState]
    public var id: Date { weekStart }

    public init(weekStart: Date, days: [DayState]) {
        self.weekStart = weekStart
        self.days = days
    }
}

/// Pain recorded at the end of a session.
public struct PainPoint: Equatable, Sendable, Identifiable {
    public let date: Date
    public let level: Int
    public var id: Date { date }

    public init(date: Date, level: Int) {
        self.date = date
        self.level = level
    }
}

/// Average pain over the last two weeks against the four weeks before.
public struct PainTrend: Equatable, Sendable {
    public let before: Double
    public let recent: Double

    public init(before: Double, recent: Double) {
        self.before = before
        self.recent = recent
    }

    public var isDown: Bool { recent < before }
}

/// How many times each rating was given in one calendar week.
public struct WeekRatings: Equatable, Sendable, Identifiable {
    public let weekStart: Date
    public let counts: [ExerciseRating: Int]
    public var id: Date { weekStart }

    public init(weekStart: Date, counts: [ExerciseRating: Int]) {
        self.weekStart = weekStart
        self.counts = counts
    }

    public var total: Int { counts.values.reduce(0, +) }
}

/// Where this week stands against the weekly goal.
public enum GoalStatus: Equatable, Sendable {
    case met
    /// At or ahead of the pace the goal needs so far this week.
    case onTrack
    case behind(remaining: Int)
}

/// One time an exercise came up, for spotting trends.
public struct RatedEntry: Equatable, Sendable {
    public let date: Date
    public let isDone: Bool
    public let rating: ExerciseRating?

    public init(date: Date, isDone: Bool, rating: ExerciseRating?) {
        self.date = date
        self.isDone = isDone
        self.rating = rating
    }
}

/// Something about one exercise worth raising with a PT. At most one per exercise.
public enum ExerciseTrend: Equatable, Sendable {
    /// Rated hard or painful `count` of the last `of` times; `before` is what it was
    /// mostly rated earlier, when that was easy or about right.
    case harder(count: Int, of: Int, before: ExerciseRating?)
    /// Rated painful recently, without a run of hard ratings.
    case painful(on: Date)
    /// Skipped `count` times in the last two weeks.
    case oftenSkipped(count: Int)
    /// Rated easy `count` of the last `of` times.
    case easier(count: Int, of: Int)
}

public extension ProgressStats {
    /// One column per calendar week, oldest first, ending with this week.
    static func heatmap(
        in sessions: [SessionRecord],
        weeks: Int,
        today: Date,
        calendar: Calendar = .current
    ) -> [HeatmapWeek] {
        guard weeks > 0, let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today) else { return [] }
        let done = Set(sessions.compactMap(\.completedAt).map { calendar.startOfDay(for: $0) })
        let tried = Set(sessions.filter { $0.completedAt == nil }.map { calendar.startOfDay(for: $0.startedAt) })
        let todayStart = calendar.startOfDay(for: today)
        return (0..<weeks).reversed().compactMap { back -> HeatmapWeek? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek.start) else { return nil }
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map { day -> DayState in
                if day > todayStart { return .future }
                if done.contains(day) { return .done }
                if tried.contains(day) { return .partial }
                return .rest
            }
            return HeatmapWeek(weekStart: start, days: days)
        }
    }

    /// The longest run of consecutive days with a completed session, from `start` through `end`.
    static func longestStreak(
        in sessions: [SessionRecord],
        from start: Date,
        through end: Date,
        calendar: Calendar = .current
    ) -> Int {
        let days = Set(sessions.compactMap(\.completedAt).map { calendar.startOfDay(for: $0) })
            .filter { $0 >= calendar.startOfDay(for: start) && $0 <= end }
            .sorted()
        var longest = 0
        var run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }
        return longest
    }

    /// Met, on pace for, or behind the weekly goal, given the days done this week.
    static func goalStatus(daysThisWeek: Int, goal: Int, today: Date, calendar: Calendar = .current) -> GoalStatus {
        if daysThisWeek >= goal { return .met }
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start else {
            return .behind(remaining: goal - daysThisWeek)
        }
        let elapsed = (calendar.dateComponents([.day], from: weekStart, to: calendar.startOfDay(for: today)).day ?? 0) + 1
        let pace = Int((Double(goal) * Double(elapsed) / 7).rounded(.down))
        return daysThisWeek >= pace ? .onTrack : .behind(remaining: goal - daysThisWeek)
    }

    /// Share of the weekly goal met, each week capped at the goal. Counts only finished
    /// weeks from the first session's week on; this week alone when there are none yet.
    static func goalShare(
        weeks: [WeekCount],
        goal: Int,
        firstSession: Date?,
        calendar: Calendar = .current
    ) -> Double? {
        guard goal > 0, let firstSession, let current = weeks.last,
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: firstSession)?.start else { return nil }
        var counted = weeks.dropLast().filter { $0.weekStart >= firstWeek }
        if counted.isEmpty { counted = [current] }
        let met = counted.reduce(0) { $0 + min($1.days, goal) }
        return Double(met) / Double(goal * counted.count)
    }

    /// Minutes a guided session ran; nil for one logged afterwards or not finished.
    static func minutes(of session: SessionRecord) -> Int? {
        guard let end = session.completedAt else { return nil }
        let seconds = end.timeIntervalSince(session.startedAt)
        // A logged session has no timing: it starts and ends at the same moment.
        guard seconds >= 30 else { return nil }
        return max(1, Int((seconds / 60).rounded()))
    }

    /// Pain recorded at the end of each session, oldest first.
    static func painPoints(in sessions: [SessionRecord]) -> [PainPoint] {
        sessions
            .compactMap { session in session.painLevel.map { PainPoint(date: session.startedAt, level: $0) } }
            .sorted { $0.date < $1.date }
    }

    /// Average pain over the last 14 days against the 28 days before, when both have at
    /// least two readings and they differ by a point or more.
    static func painTrend(_ points: [PainPoint], today: Date, calendar: Calendar = .current) -> PainTrend? {
        let todayStart = calendar.startOfDay(for: today)
        guard let recentStart = calendar.date(byAdding: .day, value: -13, to: todayStart),
              let earlierStart = calendar.date(byAdding: .day, value: -28, to: recentStart) else { return nil }
        let recent = points.filter { $0.date >= recentStart && $0.date <= today }.map(\.level)
        let earlier = points.filter { $0.date >= earlierStart && $0.date < recentStart }.map(\.level)
        guard recent.count >= 2, earlier.count >= 2 else { return nil }
        let trend = PainTrend(before: Double(earlier.reduce(0, +)) / Double(earlier.count),
                              recent: Double(recent.reduce(0, +)) / Double(recent.count))
        return abs(trend.recent - trend.before) >= 1 ? trend : nil
    }

    /// Ratings given each calendar week, oldest first, ending with this week.
    static func weeklyRatings(
        in sessions: [SessionRecord],
        weeks: Int,
        today: Date,
        calendar: Calendar = .current
    ) -> [WeekRatings] {
        guard weeks > 0, let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today) else { return [] }
        let rated = sessions.flatMap(\.exerciseRecords).compactMap { record in
            record.rating.map { (date: record.completedAt ?? record.startedAt, rating: $0) }
        }
        return (0..<weeks).reversed().compactMap { back -> WeekRatings? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek.start),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
            var counts: [ExerciseRating: Int] = [:]
            for entry in rated where entry.date >= start && entry.date < end {
                counts[entry.rating, default: 0] += 1
            }
            return WeekRatings(weekStart: start, counts: counts)
        }
    }

    /// The one thing worth raising about an exercise, if any. Checks, in order: a run of
    /// hard or painful ratings, a painful rating this week, frequent skips, a run of easy ratings.
    /// Only the last four weeks count.
    static func trend(
        newestFirst entries: [RatedEntry],
        today: Date,
        calendar: Calendar = .current
    ) -> ExerciseTrend? {
        let todayStart = calendar.startOfDay(for: today)
        guard let monthAgo = calendar.date(byAdding: .day, value: -28, to: todayStart),
              let twoWeeksAgo = calendar.date(byAdding: .day, value: -13, to: todayStart),
              let weekAgo = calendar.date(byAdding: .day, value: -6, to: todayStart) else { return nil }

        let ratings = entries.compactMap { entry in entry.rating.map { (date: entry.date, rating: $0) } }
        let recent = Array(ratings.prefix(4).filter { $0.date >= monthAgo })

        if recent.count >= 3 {
            let hard = recent.filter { $0.rating == .hard || $0.rating == .painful }.count
            if hard >= 3 {
                let earlier = ratings.dropFirst(recent.count).prefix(8).map { $0.rating }
                return .harder(count: hard, of: recent.count, before: mostly(earlier))
            }
        }
        if let painful = ratings.first(where: { $0.rating == .painful && $0.date >= weekAgo }) {
            return .painful(on: painful.date)
        }
        let skips = entries.filter { !$0.isDone && $0.date >= twoWeeksAgo }.count
        if skips >= 3 { return .oftenSkipped(count: skips) }
        if recent.count >= 3 {
            let easy = recent.filter { $0.rating == .easy }.count
            if easy >= 3 { return .easier(count: easy, of: recent.count) }
        }
        return nil
    }

    /// The rating given more than half the time, when it's easy or about right.
    private static func mostly(_ ratings: [ExerciseRating]) -> ExerciseRating? {
        guard !ratings.isEmpty else { return nil }
        for rating in [ExerciseRating.aboutRight, .easy] {
            if ratings.filter({ $0 == rating }).count * 2 > ratings.count { return rating }
        }
        return nil
    }
}
