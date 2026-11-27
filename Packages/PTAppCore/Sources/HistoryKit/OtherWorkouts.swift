import Foundation
import DataKit

/// A kind of workout from Apple Health, such as running or yoga.
public struct WorkoutActivity: Hashable, Codable, Sendable, Identifiable {
    /// Apple Health's activity type number.
    public let id: UInt
    public let name: String
    /// A few capital letters for tight spots, like under a day in the week strip.
    public let tag: String

    public init(id: UInt, name: String, tag: String) {
        self.id = id
        self.name = name
        self.tag = tag
    }
}

/// A workout recorded outside Mend: by a Watch, Strava, Peloton or anything else
/// that writes to Apple Health.
public struct OtherWorkout: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let activity: WorkoutActivity
    public let start: Date
    public let end: Date
    public let distanceMeters: Double?

    public init(id: UUID, activity: WorkoutActivity, start: Date, end: Date, distanceMeters: Double? = nil) {
        self.id = id
        self.activity = activity
        self.start = start
        self.end = end
        self.distanceMeters = distanceMeters
    }

    public var minutes: Int { max(1, Int((end.timeIntervalSince(start) / 60).rounded())) }
}

/// Which exercises a kind of workout covers, as set by the person.
public struct CoverageRule: Codable, Equatable, Sendable, Identifiable {
    public var activity: WorkoutActivity
    /// Exercise lineages, so a rule survives a new sheet from the PT.
    public var exerciseLineages: Set<UUID>
    public var minimumMinutes: Int
    /// Offer on Today before counting; otherwise count as soon as the workout shows up.
    public var asksFirst: Bool

    public var id: UInt { activity.id }

    public init(activity: WorkoutActivity, exerciseLineages: Set<UUID> = [], minimumMinutes: Int = 20,
                asksFirst: Bool = true) {
        self.activity = activity
        self.exerciseLineages = exerciseLineages
        self.minimumMinutes = minimumMinutes
        self.asksFirst = asksFirst
    }

    /// Whether the workout is this kind, long enough, and covers anything.
    public func applies(to workout: OtherWorkout) -> Bool {
        workout.activity.id == activity.id && workout.minutes >= minimumMinutes && !exerciseLineages.isEmpty
    }
}

/// Totals for one kind of workout.
public struct ActivitySummary: Equatable, Sendable, Identifiable {
    public let activity: WorkoutActivity
    public let count: Int
    public let minutes: Int
    public let distanceMeters: Double?
    public var id: UInt { activity.id }

    public init(activity: WorkoutActivity, count: Int, minutes: Int, distanceMeters: Double?) {
        self.activity = activity
        self.count = count
        self.minutes = minutes
        self.distanceMeters = distanceMeters
    }
}

/// Average pain after sessions within a day of one kind of workout, against other sessions.
public struct NextDayPain: Equatable, Sendable {
    public let after: Double
    public let otherwise: Double
    /// Pain readings that followed the workout.
    public let count: Int

    public init(after: Double, otherwise: Double, count: Int) {
        self.after = after
        self.otherwise = otherwise
        self.count = count
    }

    public var isHigher: Bool { after > otherwise }
}

public enum OtherWorkoutStats {
    /// How long after a workout a session's pain reading counts as "after" it.
    public static let followingWindow: TimeInterval = 30 * 3600

    /// Exercises another workout stood in for on a day, each with the workout's name.
    public static func coveredExercises(
        on day: Date,
        in sessions: [SessionRecord],
        calendar: Calendar = .current
    ) -> [UUID: String] {
        let start = calendar.startOfDay(for: day)
        var covered: [UUID: String] = [:]
        for session in sessions where calendar.startOfDay(for: session.startedAt) == start {
            for record in session.exerciseRecords {
                if let name = record.coveredBy { covered[record.exerciseID] = name }
            }
        }
        return covered
    }

    /// Exercises done in Mend on a day, in any session.
    public static func doneExercises(
        on day: Date,
        in sessions: [SessionRecord],
        calendar: Calendar = .current
    ) -> Set<UUID> {
        let start = calendar.startOfDay(for: day)
        return Set(sessions
            .filter { calendar.startOfDay(for: $0.startedAt) == start }
            .flatMap(\.exerciseRecords)
            .filter { $0.status == .completed }
            .map(\.exerciseID))
    }

    /// Each kind of workout with its totals, most frequent first.
    public static func summaries(of workouts: [OtherWorkout]) -> [ActivitySummary] {
        Dictionary(grouping: workouts, by: \.activity)
            .map { activity, group in
                let distances = group.compactMap(\.distanceMeters)
                return ActivitySummary(activity: activity,
                                       count: group.count,
                                       minutes: group.reduce(0) { $0 + $1.minutes },
                                       distanceMeters: distances.isEmpty ? nil : distances.reduce(0, +))
            }
            .sorted { ($0.count, $0.minutes, $1.activity.name) > ($1.count, $1.minutes, $0.activity.name) }
    }

    /// Pain after sessions that came within a day of this kind of workout, against
    /// sessions that didn't. Needs three readings each side and a point of difference.
    public static func nextDayPain(
        points: [PainPoint],
        workouts: [OtherWorkout],
        activityID: UInt
    ) -> NextDayPain? {
        let ends = workouts.filter { $0.activity.id == activityID }.map(\.end)
        var after: [Int] = []
        var otherwise: [Int] = []
        for point in points {
            let follows = ends.contains { $0 <= point.date && point.date.timeIntervalSince($0) <= followingWindow }
            if follows { after.append(point.level) } else { otherwise.append(point.level) }
        }
        guard after.count >= 3, otherwise.count >= 3 else { return nil }
        let result = NextDayPain(after: Double(after.reduce(0, +)) / Double(after.count),
                                 otherwise: Double(otherwise.reduce(0, +)) / Double(otherwise.count),
                                 count: after.count)
        return abs(result.after - result.otherwise) >= 1 ? result : nil
    }

    /// Start-of-day dates with at least one workout.
    public static func days(of workouts: [OtherWorkout], calendar: Calendar = .current) -> Set<Date> {
        Set(workouts.map { calendar.startOfDay(for: $0.start) })
    }

    /// The kind of the longest workout on each day, keyed by start of day.
    public static func mainActivities(of workouts: [OtherWorkout],
                                      calendar: Calendar = .current) -> [Date: WorkoutActivity] {
        Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.start) }
            .compactMapValues { day in day.max { $0.minutes < $1.minutes }?.activity }
    }

    /// The shortest workout that counts toward the weekly goal and streak.
    public static let countingMinutes = 10

    /// Start-of-day dates with a workout long enough to count toward the goal and streak.
    public static func countingDays(of workouts: [OtherWorkout], calendar: Calendar = .current) -> Set<Date> {
        days(of: workouts.filter { $0.minutes >= countingMinutes }, calendar: calendar)
    }
}
