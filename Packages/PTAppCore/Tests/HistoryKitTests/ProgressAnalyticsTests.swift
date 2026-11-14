import XCTest
import DataKit
@testable import HistoryKit

final class ProgressAnalyticsTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }

    private func day(_ d: Int, month: Int = 11, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: d, hour: hour))!
    }

    // Wed 11 Nov 2026 is in the week starting Mon 9 Nov.
    private var today: Date { day(11, hour: 15) }

    private func complete(on date: Date, pain: Int? = nil, records: [ExerciseRecord] = []) -> SessionRecord {
        let session = SessionRecord(routineID: UUID(), startedAt: date, completedAt: date, exerciseRecords: records)
        session.painLevel = pain
        return session
    }

    private func rated(_ rating: ExerciseRating?, on date: Date, done: Bool = true) -> RatedEntry {
        RatedEntry(date: date, isDone: done, rating: rating)
    }

    // MARK: Range

    func test_range_weekCounts() {
        XCTAssertEqual(ProgressRange.fourWeeks.weekCount(firstSession: nil, today: today, calendar: calendar), 4)
        XCTAssertEqual(ProgressRange.threeMonths.weekCount(firstSession: nil, today: today, calendar: calendar), 13)
        XCTAssertEqual(ProgressRange.all.weekCount(firstSession: day(1, month: 9), today: today, calendar: calendar), 11,
                       "the week of Mon 31 Aug through this week")
        XCTAssertEqual(ProgressRange.all.weekCount(firstSession: day(10), today: today, calendar: calendar), 4,
                       "never fewer than four weeks")
    }

    // MARK: Heatmap and streaks

    func test_heatmap_marksDoneAndPartialDays_andTheRestOfThisWeekAsFuture() {
        let sessions = [
            complete(on: day(9)),
            SessionRecord(routineID: UUID(), startedAt: day(10)),   // started, not finished
            complete(on: day(3)),
        ]

        let weeks = ProgressStats.heatmap(in: sessions, weeks: 2, today: today, calendar: calendar)

        XCTAssertEqual(weeks.map(\.weekStart), [day(2, hour: 0), day(9, hour: 0)])
        XCTAssertEqual(weeks[0].days, [.rest, .done, .rest, .rest, .rest, .rest, .rest])
        XCTAssertEqual(weeks[1].days, [.done, .partial, .rest, .future, .future, .future, .future])
    }

    func test_longestStreak_countsTheLongestRunInTheWindow() {
        let sessions = [day(1), day(2), day(3), day(5), day(6), day(8), day(9), day(10), day(11)].map { complete(on: $0) }

        XCTAssertEqual(ProgressStats.longestStreak(in: sessions, from: day(1, hour: 0), through: today, calendar: calendar), 4)
        XCTAssertEqual(ProgressStats.longestStreak(in: sessions, from: day(1, hour: 0), through: day(6, hour: 23),
                                                   calendar: calendar), 3)
        XCTAssertEqual(ProgressStats.longestStreak(in: [], from: day(1), through: today, calendar: calendar), 0)
    }

    // MARK: Goal

    func test_goalStatus_metOnTrackOrBehind() {
        // Wednesday is day 3 of the week: a 5-day goal needs 2 days by now to be on pace.
        XCTAssertEqual(ProgressStats.goalStatus(daysThisWeek: 5, goal: 5, today: today, calendar: calendar), .met)
        XCTAssertEqual(ProgressStats.goalStatus(daysThisWeek: 2, goal: 5, today: today, calendar: calendar), .onTrack)
        XCTAssertEqual(ProgressStats.goalStatus(daysThisWeek: 1, goal: 5, today: today, calendar: calendar),
                       .behind(remaining: 4))
    }

    func test_goalShare_countsFinishedWeeksSinceTheFirstSession_cappedAtTheGoal() {
        let weeks = [
            WeekCount(weekStart: day(19, month: 10, hour: 0), days: 0),  // before the first session
            WeekCount(weekStart: day(26, month: 10, hour: 0), days: 7),  // capped at 5
            WeekCount(weekStart: day(2, hour: 0), days: 2),
            WeekCount(weekStart: day(9, hour: 0), days: 1),              // this week: not counted
        ]

        let share = ProgressStats.goalShare(weeks: weeks, goal: 5, firstSession: day(27, month: 10), calendar: calendar)

        XCTAssertEqual(share, 0.7)
    }

    func test_goalShare_inTheFirstWeek_usesThisWeek() {
        let weeks = [WeekCount(weekStart: day(2, hour: 0), days: 0), WeekCount(weekStart: day(9, hour: 0), days: 2)]
        XCTAssertEqual(ProgressStats.goalShare(weeks: weeks, goal: 4, firstSession: day(9), calendar: calendar), 0.5)
        XCTAssertNil(ProgressStats.goalShare(weeks: weeks, goal: 4, firstSession: nil, calendar: calendar))
    }

    // MARK: Pain

    func test_painTrend_comparesTheLastTwoWeeksWithTheFourBefore() {
        let points = [
            PainPoint(date: day(20, month: 10), level: 5),
            PainPoint(date: day(24, month: 10), level: 4),
            PainPoint(date: day(2), level: 2),
            PainPoint(date: day(10), level: 1),
        ]

        XCTAssertEqual(ProgressStats.painTrend(points, today: today, calendar: calendar),
                       PainTrend(before: 4.5, recent: 1.5))
    }

    func test_painTrend_needsTwoReadingsEachSide_andAPointOfChange() {
        let few = [PainPoint(date: day(24, month: 10), level: 5), PainPoint(date: day(10), level: 1)]
        XCTAssertNil(ProgressStats.painTrend(few, today: today, calendar: calendar))

        let flat = [3, 3, 3, 2].enumerated().map { index, level in
            PainPoint(date: index < 2 ? day(20 + index, month: 10) : day(5 + index), level: level)
        }
        XCTAssertNil(ProgressStats.painTrend(flat, today: today, calendar: calendar), "half a point isn't a trend")
    }

    func test_painPoints_andMinutes() {
        let guided = SessionRecord(routineID: UUID(), startedAt: day(10), completedAt: day(10).addingTimeInterval(12 * 60))
        guided.painLevel = 3
        let logged = complete(on: day(9))

        XCTAssertEqual(ProgressStats.painPoints(in: [guided, logged]), [PainPoint(date: day(10), level: 3)])
        XCTAssertEqual(ProgressStats.minutes(of: guided), 12)
        XCTAssertNil(ProgressStats.minutes(of: logged), "a logged session has no timing")
    }

    // MARK: Ratings

    func test_weeklyRatings_countsEachRatingPerWeek() {
        let id = UUID()
        func record(_ rating: ExerciseRating?, _ date: Date) -> ExerciseRecord {
            let record = ExerciseRecord(exerciseID: id, status: .completed, startedAt: date, completedAt: date)
            record.rating = rating
            return record
        }
        let sessions = [
            complete(on: day(3), records: [record(.easy, day(3)), record(.hard, day(3))]),
            complete(on: day(10), records: [record(.hard, day(10)), record(.hard, day(10)), record(nil, day(10))]),
        ]

        let weeks = ProgressStats.weeklyRatings(in: sessions, weeks: 2, today: today, calendar: calendar)

        XCTAssertEqual(weeks.map(\.counts), [[.easy: 1, .hard: 1], [.hard: 2]])
        XCTAssertEqual(weeks.map(\.total), [2, 2])
    }

    // MARK: Trends

    func test_trend_harderLately_afterMostlyAboutRight() {
        let entries = [
            rated(.hard, on: day(11)), rated(.painful, on: day(10)), rated(.hard, on: day(8)), rated(.aboutRight, on: day(6)),
            rated(.aboutRight, on: day(4)), rated(.aboutRight, on: day(2)), rated(.easy, on: day(30, month: 10)),
        ]

        XCTAssertEqual(ProgressStats.trend(newestFirst: entries, today: today, calendar: calendar),
                       .harder(count: 3, of: 4, before: .aboutRight))
    }

    func test_trend_harder_ignoresRatingsOlderThanFourWeeks() {
        let old = [rated(.hard, on: day(1, month: 9)), rated(.hard, on: day(2, month: 9)), rated(.hard, on: day(3, month: 9))]
        XCTAssertNil(ProgressStats.trend(newestFirst: old, today: today, calendar: calendar))
    }

    func test_trend_painfulThisWeek() {
        let entries = [rated(.aboutRight, on: day(11)), rated(.painful, on: day(9)), rated(.easy, on: day(5))]
        XCTAssertEqual(ProgressStats.trend(newestFirst: entries, today: today, calendar: calendar), .painful(on: day(9)))
    }

    func test_trend_oftenSkipped() {
        let entries = [rated(nil, on: day(11), done: false), rated(nil, on: day(9), done: false),
                       rated(nil, on: day(1), done: false), rated(nil, on: day(1, month: 10), done: false)]
        XCTAssertEqual(ProgressStats.trend(newestFirst: entries, today: today, calendar: calendar), .oftenSkipped(count: 3))
    }

    func test_trend_easierLately() {
        let entries = [rated(.easy, on: day(11)), rated(.easy, on: day(9)), rated(.aboutRight, on: day(7)),
                       rated(.easy, on: day(5))]
        XCTAssertEqual(ProgressStats.trend(newestFirst: entries, today: today, calendar: calendar), .easier(count: 3, of: 4))
    }

    func test_trend_nothingWorthRaising() {
        let entries = [rated(.aboutRight, on: day(11)), rated(.hard, on: day(9)), rated(.aboutRight, on: day(7))]
        XCTAssertNil(ProgressStats.trend(newestFirst: entries, today: today, calendar: calendar))
    }
}
