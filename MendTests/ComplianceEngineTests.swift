import XCTest
@testable import Mend

final class ComplianceEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    func testDayStreakCountsConsecutiveDays() {
        let now = date(2026, 8, 29)
        let sessions = [date(2026, 8, 29), date(2026, 8, 28), date(2026, 8, 27)]
        XCTAssertEqual(ComplianceEngine.dayStreak(sessionDates: sessions, calendar: calendar, now: now), 3)
    }

    func testDayStreakSurvivesUntilDayIsMissed() {
        // Nothing today yet, but yesterday and the day before are done.
        let now = date(2026, 8, 29)
        let sessions = [date(2026, 8, 28), date(2026, 8, 27)]
        XCTAssertEqual(ComplianceEngine.dayStreak(sessionDates: sessions, calendar: calendar, now: now), 2)
    }

    func testDayStreakBreaksOnGap() {
        let now = date(2026, 8, 29)
        let sessions = [date(2026, 8, 26), date(2026, 8, 25)]
        XCTAssertEqual(ComplianceEngine.dayStreak(sessionDates: sessions, calendar: calendar, now: now), 0)
    }

    func testTwoSessionsInOneDayCountOnce() {
        let now = date(2026, 8, 29)
        let sessions = [date(2026, 8, 29, hour: 8), date(2026, 8, 29, hour: 18)]
        let count = ComplianceEngine.currentWeekCount(sessionDates: sessions, calendar: calendar, now: now)
        XCTAssertEqual(count, 1)
    }

    func testWeekStatsBucketsDistinctDaysPerWeek() {
        // 2026-08-29 is a Saturday; the gregorian week (Sunday start) runs 8/23–8/29.
        let now = date(2026, 8, 29)
        let sessions = [
            date(2026, 8, 24), date(2026, 8, 26), date(2026, 8, 28), // this week: 3 days
            date(2026, 8, 18), date(2026, 8, 19)                     // last week: 2 days
        ]
        let stats = ComplianceEngine.weekStats(sessionDates: sessions, target: 3, weeks: 2, calendar: calendar, now: now)
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats[0].sessions, 2)
        XCTAssertFalse(stats[0].metTarget)
        XCTAssertEqual(stats[1].sessions, 3)
        XCTAssertTrue(stats[1].metTarget)
    }

    func testWeekStreakToleratesInProgressWeek() {
        // Last two full weeks met a 2×/week target; this week has nothing yet.
        let now = date(2026, 8, 24) // Monday
        let sessions = [
            date(2026, 8, 17), date(2026, 8, 19), // previous week
            date(2026, 8, 10), date(2026, 8, 12)  // week before
        ]
        XCTAssertEqual(
            ComplianceEngine.weekStreak(sessionDates: sessions, target: 2, calendar: calendar, now: now),
            2
        )
    }
}
