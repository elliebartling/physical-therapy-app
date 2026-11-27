import Foundation
import DataKit

/// Where a day stands: what's done, what's left, and whether it's complete.
public enum DayProgress {
    /// Exercises done on the day in any session, including ones another workout covered.
    public static func finished(on day: Date, in sessions: [SessionRecord], calendar: Calendar = .current) -> Set<UUID> {
        OtherWorkoutStats.doneExercises(on: day, in: sessions, calendar: calendar)
    }

    /// Whether a session finished on the day.
    public static func isComplete(on day: Date, in sessions: [SessionRecord], calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: day)
        return sessions.contains { $0.completedAt.map { calendar.startOfDay(for: $0) == start } ?? false }
    }

    /// What Start leaves out: what's already done today, so a session started again
    /// carries on from there. Nothing once the day is complete: Start again runs it all.
    public static func skipping(on day: Date, in sessions: [SessionRecord], calendar: Calendar = .current) -> Set<UUID> {
        isComplete(on: day, in: sessions, calendar: calendar) ? [] : finished(on: day, in: sessions, calendar: calendar)
    }

    /// Whether every required exercise is among `done`. Optional ones never hold a day back.
    public static func coversRequired(_ exercises: [Exercise], done: Set<UUID>) -> Bool {
        exercises.filter { !$0.isOptional }.allSatisfy { done.contains($0.id) }
    }
}
