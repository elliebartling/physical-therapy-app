import Foundation
import Observation
import DataKit
import HistoryKit
import os

private let logger = Logger(subsystem: "PTAppCore", category: "progress")

/// Everything the Progress tab shows: the weekly goal, consistency, pain, how
/// exercises felt, what's worth telling a PT, each exercise, and every session.
@MainActor
@Observable
public final class ProgressViewModel {
    /// One time an exercise came up, as a small square: its rating, done without one, or skipped.
    public enum Mark: Equatable, Sendable {
        case rated(ExerciseRating)
        case done
        case skipped
    }

    public struct ExerciseRow: Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public let prescription: String
        public let stats: ExerciseStats
        /// The most recent rating it was given, if any.
        public let lastRating: ExerciseRating?
        /// The last few times it came up, oldest first.
        public let recent: [Mark]
        public let trend: ExerciseTrend?
    }

    public struct SessionItem: Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public let isDone: Bool
        public let rating: ExerciseRating?
    }

    public struct SessionRow: Identifiable, Equatable {
        public let id: UUID
        public let date: Date
        public let isComplete: Bool
        /// Timed in the app; nil for a session logged afterwards.
        public let minutes: Int?
        public let items: [SessionItem]
        public let painLevel: Int?
        public let note: String?
        public var doneCount: Int { items.filter(\.isDone).count }
    }

    public struct Month: Identifiable, Equatable {
        public let id: Date
        public let title: String
        public let sessions: [SessionRow]
    }

    /// One time an exercise came up in a session.
    public struct ExerciseEntry: Identifiable, Equatable {
        public let id: UUID
        public let date: Date
        public let isDone: Bool
        public let rating: ExerciseRating?
        /// What was prescribed at the time.
        public let prescription: String?

        var mark: Mark {
            guard isDone else { return .skipped }
            return rating.map(Mark.rated) ?? .done
        }
    }

    /// Something worth raising with a PT.
    public struct Insight: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let detail: String
        /// The exercise it's about, if any.
        public let exerciseID: UUID?
    }

    /// One phase of an exercise's prescription.
    public struct Phase: Identifiable, Equatable {
        public let id: UUID
        public let number: Int
        public let start: Date
        /// When the next phase began; nil for the current one.
        public let end: Date?
        public let prescription: String
    }

    public static let defaultWeeklyGoal = 5
    static let weeklyGoalKey = "weeklyGoalDays"
    /// Squares shown per exercise in the list.
    static let recentCount = 8
    /// The heatmap stays legible up to about half a year of columns.
    static let maxHeatmapWeeks = 26

    public var range: ProgressRange = .threeMonths {
        didSet { if range != oldValue { buildRange() } }
    }

    /// Days a week to aim for, 1–7. Remembered between launches.
    public var weeklyGoal: Int {
        didSet {
            defaults.set(goal, forKey: Self.weeklyGoalKey)
            buildRange()
        }
    }

    // This week and the goal
    public private(set) var daysThisWeek = 0
    public private(set) var goalStatus: GoalStatus = .onTrack
    /// Share of the weekly goal met across the range; nil before any session.
    public private(set) var goalShare: Double?

    // Across the range
    public private(set) var weeks: [WeekCount] = []
    public private(set) var activeDays = 0
    public private(set) var minutes = 0
    public private(set) var heatmap: [HeatmapWeek] = []
    public private(set) var longestStreak = 0
    public private(set) var painPoints: [PainPoint] = []
    public private(set) var ratingWeeks: [WeekRatings] = []

    // Now
    public private(set) var streak = 0
    public private(set) var painNow: Int?
    /// The first pain reading in the range, when it differs from the latest.
    public private(set) var painFrom: Int?
    public private(set) var insights: [Insight] = []

    // Lists
    public private(set) var exercises: [ExerciseRow] = []
    public private(set) var months: [Month] = []
    public private(set) var errorMessage: String?

    public var hasSessions: Bool { !months.isEmpty }
    /// The weekly goal, kept within a week.
    private var goal: Int { min(max(weeklyGoal, 1), 7) }
    public var sessionCount: Int { sessions.count }
    public var routineName: String? { routines.first(where: \.isActive)?.name }

    private let routineRepo: RoutineRepository
    private let sessionRepo: SessionRepository
    private let defaults: UserDefaults
    private let today: Date
    private let calendar: Calendar
    private var sessions: [SessionRecord] = []
    private var routines: [Routine] = []
    private var names: [UUID: String] = [:]
    private var order: [UUID: Int] = [:]
    private var prescriptions: [UUID: String] = [:]
    /// Exercise id → lineage, so one exercise's history spans routine phases.
    private var lineage: [UUID: UUID] = [:]

    public init(routineRepo: RoutineRepository, sessionRepo: SessionRepository,
                defaults: UserDefaults = .standard, today: Date = .now, calendar: Calendar = .current) {
        self.routineRepo = routineRepo
        self.sessionRepo = sessionRepo
        self.defaults = defaults
        self.today = today
        self.calendar = calendar
        let stored = defaults.integer(forKey: Self.weeklyGoalKey)
        self.weeklyGoal = (1...7).contains(stored) ? stored : Self.defaultWeeklyGoal
    }

    public func refresh() {
        do {
            sessions = try sessionRepo.fetchAll()
            routines = try routineRepo.fetchAll()
            errorMessage = nil
            build()
        } catch {
            logger.error("Loading progress failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't load your history. Try again."
        }
    }

    /// Every time the exercise came up, in this phase or earlier ones, newest first.
    public func entries(forExercise id: UUID) -> [ExerciseEntry] {
        let group = lineage[id] ?? id
        return sessions
            .flatMap(\.exerciseRecords)
            .filter { (lineage[$0.exerciseID] ?? $0.exerciseID) == group }
            .map { ExerciseEntry(id: $0.id, date: $0.completedAt ?? $0.startedAt,
                                 isDone: $0.status == .completed, rating: $0.rating,
                                 prescription: prescriptions[$0.exerciseID]) }
            .sorted { $0.date > $1.date }
    }

    /// The last `count` times the exercise came up, oldest first.
    public func marks(forExercise id: UUID, count: Int) -> [Mark] {
        entries(forExercise: id).prefix(count).reversed().map(\.mark)
    }

    /// Each phase the exercise was prescribed in, oldest first.
    public func phases(forExercise id: UUID) -> [Phase] {
        let group = lineage[id] ?? id
        let ordered = routines.sorted { ($0.phase, $0.createdAt) < ($1.phase, $1.createdAt) }
        let found = ordered.enumerated().compactMap { index, routine -> (Routine, Exercise, Date?)? in
            guard let exercise = routine.exercises.first(where: { $0.lineageID == group }) else { return nil }
            let next = ordered.indices.contains(index + 1) ? ordered[index + 1].createdAt : nil
            return (routine, exercise, next)
        }
        // Numbered by position, so routines set up from scratch (each "phase 1") still read in order.
        return found.enumerated().map { position, item in
            let (routine, exercise, next) = item
            return Phase(id: routine.id, number: position + 1, start: routine.createdAt, end: next,
                         prescription: Prescription.text(target: exercise.target, side: exercise.side))
        }
    }

    public func exercise(id: UUID) -> ExerciseRow? { exercises.first { $0.id == id } }

    /// The insight about one exercise, if there is one.
    public func insight(forExercise id: UUID) -> Insight? {
        insights.first { $0.exerciseID == id }
    }

    public func session(id: UUID) -> SessionRow? {
        months.lazy.flatMap(\.sessions).first { $0.id == id }
    }

    /// Deletes a session, e.g. one logged by mistake. Returns whether it worked.
    @discardableResult
    public func deleteSession(id: UUID) -> Bool {
        guard let record = sessions.first(where: { $0.id == id }) else { return false }
        do {
            try sessionRepo.delete(record)
            refresh()
            return true
        } catch {
            logger.error("Deleting a session failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't delete that session. Try again."
            return false
        }
    }

    public func dismissError() { errorMessage = nil }

    // MARK: Building

    private var firstSessionDate: Date? { sessions.map(\.startedAt).min() }

    private func build() {
        // Names come from every routine, so sessions from a replaced routine still read well.
        let allExercises = routines.flatMap(\.exercises)
        names = Dictionary(allExercises.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        order = Dictionary(allExercises.map { ($0.id, $0.order) }, uniquingKeysWith: { first, _ in first })
        lineage = Dictionary(allExercises.map { ($0.id, $0.lineageID) }, uniquingKeysWith: { first, _ in first })
        prescriptions = Dictionary(
            allExercises.map { ($0.id, Prescription.text(target: $0.target, side: $0.side)) },
            uniquingKeysWith: { first, _ in first }
        )
        streak = StreakCalculator.currentStreak(in: sessions, today: today, calendar: calendar)

        let stats = ProgressStats.exerciseStats(in: sessions, groupedBy: { [lineage] in lineage[$0] ?? $0 })
        let active = routines.first(where: \.isActive)?.orderedExercises ?? []
        exercises = active.map { exercise in
            let history = entries(forExercise: exercise.id)
            return ExerciseRow(
                id: exercise.id,
                name: exercise.name,
                prescription: Prescription.text(target: exercise.target, side: exercise.side),
                stats: stats[exercise.lineageID] ?? ExerciseStats(),
                lastRating: history.first(where: { $0.rating != nil })?.rating,
                recent: history.prefix(Self.recentCount).reversed().map(\.mark),
                trend: ProgressStats.trend(
                    newestFirst: history.map { RatedEntry(date: $0.date, isDone: $0.isDone, rating: $0.rating) },
                    today: today, calendar: calendar
                )
            )
        }

        let rows = sessions.sorted { $0.startedAt > $1.startedAt }.map(row(for:))
        let byMonth = Dictionary(grouping: rows) { row in
            calendar.dateInterval(of: .month, for: row.date)?.start ?? row.date
        }
        months = byMonth.keys.sorted(by: >).map { start in
            Month(id: start,
                  title: start.formatted(.dateTime.month(.wide).year()),
                  sessions: byMonth[start] ?? [])
        }
        buildRange()
    }

    /// Everything that depends on the range or the goal.
    private func buildRange() {
        let count = range.weekCount(firstSession: firstSessionDate, today: today, calendar: calendar)
        weeks = ProgressStats.weeklyDays(in: sessions, weeks: count, today: today, calendar: calendar)
        activeDays = weeks.reduce(0) { $0 + $1.days }
        daysThisWeek = weeks.last?.days ?? 0
        goalStatus = ProgressStats.goalStatus(daysThisWeek: daysThisWeek, goal: goal, today: today, calendar: calendar)
        goalShare = ProgressStats.goalShare(weeks: weeks, goal: goal, firstSession: firstSessionDate, calendar: calendar)

        let start = weeks.first?.weekStart ?? today
        let inRange = sessions.filter { $0.startedAt >= start }
        minutes = inRange.compactMap(ProgressStats.minutes(of:)).reduce(0, +)
        heatmap = ProgressStats.heatmap(in: sessions, weeks: min(count, Self.maxHeatmapWeeks), today: today,
                                        calendar: calendar)
        longestStreak = ProgressStats.longestStreak(in: sessions, from: start, through: today, calendar: calendar)
        painPoints = ProgressStats.painPoints(in: inRange)
        painNow = painPoints.last?.level
        painFrom = painPoints.count > 1 && painPoints.first?.level != painNow ? painPoints.first?.level : nil
        ratingWeeks = ProgressStats.weeklyRatings(in: sessions, weeks: count, today: today, calendar: calendar)
        insights = buildInsights()
    }

    private func buildInsights() -> [Insight] {
        var found: [Insight] = exercises.compactMap { row -> Insight? in
            row.trend.map { trend -> Insight in
                let copy = Self.copy(for: trend)
                return Insight(id: row.id.uuidString, title: "\(row.name) — \(copy.title)", detail: copy.detail,
                               exerciseID: row.id)
            }
        }
        if let pain = ProgressStats.painTrend(ProgressStats.painPoints(in: sessions), today: today, calendar: calendar) {
            let recent = Self.format(pain.recent)
            let before = Self.format(pain.before)
            found.append(Insight(
                id: "pain",
                title: pain.isDown ? "Pain — down" : "Pain — up",
                detail: "Average pain after sessions was \(recent) over the last two weeks, "
                    + "\(pain.isDown ? "down" : "up") from \(before) the four weeks before.",
                exerciseID: nil
            ))
        }
        return found
    }

    static func copy(for trend: ExerciseTrend) -> (title: String, detail: String) {
        switch trend {
        case let .harder(count, of, before):
            let after = before.map { ", after mostly “\($0.title.lowercased())”" } ?? ""
            return ("Harder lately", "Rated hard or painful \(count) of the last \(of) times\(after).")
        case .painful(let date):
            return ("Painful", "Rated painful on \(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).")
        case .oftenSkipped(let count):
            return ("Often skipped", "Skipped \(count) times in the last two weeks.")
        case let .easier(count, of):
            return ("Easier lately", "Rated easy \(count) of the last \(of) times. Worth asking whether to progress it.")
        }
    }

    /// The short tag shown beside an exercise in the list.
    static func flag(for trend: ExerciseTrend) -> String {
        switch trend {
        case .harder: "↑ Harder"
        case .painful: "Painful"
        case .oftenSkipped(let count): "\(count) skips"
        case .easier: "↓ Easier"
        }
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func row(for session: SessionRecord) -> SessionRow {
        let items = session.exerciseRecords
            .sorted {
                // A logged session stamps every exercise with the same time; fall back to routine order.
                ($0.startedAt, order[$0.exerciseID] ?? .max) < ($1.startedAt, order[$1.exerciseID] ?? .max)
            }
            .map { record in
                SessionItem(id: record.id,
                            name: names[record.exerciseID] ?? "Removed exercise",
                            isDone: record.status == .completed,
                            rating: record.rating)
            }
        return SessionRow(id: session.id, date: session.startedAt,
                          isComplete: session.isComplete, minutes: ProgressStats.minutes(of: session), items: items,
                          painLevel: session.painLevel, note: session.note)
    }

    // MARK: Visit summary

    /// A plain-text summary of the range to share with a PT.
    public func visitSummary() -> String {
        let start = weeks.first?.weekStart ?? today
        let period = "\(start.formatted(.dateTime.month(.abbreviated).day())) – "
            + today.formatted(.dateTime.month(.abbreviated).day().year())
        var lines: [String] = []
        var heading = "PT summary"
        if let name = routineName {
            let phase = routines.first(where: \.isActive)?.phase ?? 1
            heading += " — \(name)" + (phase > 1 ? ", phase \(phase)" : "")
        }
        lines.append(heading)
        lines.append(period)

        lines.append("")
        lines.append("CONSISTENCY")
        let weekWord = weeks.count == 1 ? "week" : "weeks"
        var consistency = "• \(activeDays) \(activeDays == 1 ? "day" : "days") with a full session in \(weeks.count) \(weekWord)"
        consistency += " (goal \(goal) a week"
        if let goalShare { consistency += ", \(goalShare.formatted(.percent.precision(.fractionLength(0)))) of goal" }
        consistency += ")"
        lines.append(consistency)
        if minutes > 0 { lines.append("• \(minutes) minutes of guided sessions") }
        if longestStreak > 1 { lines.append("• Longest streak \(longestStreak) days") }

        if let painNow {
            lines.append("")
            lines.append("PAIN AFTER SESSIONS (0–10)")
            var pain = "• Latest \(painNow)"
            if let painFrom { pain += ", first in this period \(painFrom)" }
            pain += " (\(painPoints.count) \(painPoints.count == 1 ? "reading" : "readings"))"
            lines.append(pain)
        }

        if !insights.isEmpty {
            lines.append("")
            lines.append("WORTH MENTIONING")
            lines += insights.map { "• \($0.title): \($0.detail)" }
        }

        if !exercises.isEmpty {
            lines.append("")
            lines.append("EXERCISES")
            for row in exercises {
                let history = entries(forExercise: row.id).filter { $0.date >= start }
                let done = history.filter(\.isDone).count
                let skipped = history.count - done
                var line = "• \(row.name) (\(row.prescription)): done \(done)"
                if skipped > 0 { line += ", skipped \(skipped)" }
                let tally = ExerciseRating.allCases.compactMap { rating -> String? in
                    let n = history.filter { $0.rating == rating }.count
                    return n == 0 ? nil : "\(n) \(rating.title.lowercased())"
                }
                if !tally.isEmpty { line += ". Felt: " + tally.joined(separator: ", ") }
                lines.append(line)
            }
        }

        let notes = sessions
            .filter { $0.startedAt >= start }
            .compactMap { session -> (Date, String)? in
                guard let note = session.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
                    return nil
                }
                return (session.startedAt, note)
            }
            .sorted { $0.0 < $1.0 }
        if !notes.isEmpty {
            lines.append("")
            lines.append("MY NOTES")
            lines += notes.map { "• \($0.0.formatted(.dateTime.month(.abbreviated).day())): \($0.1)" }
        }
        return lines.joined(separator: "\n")
    }
}
