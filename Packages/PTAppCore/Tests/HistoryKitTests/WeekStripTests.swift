import XCTest
import DataKit
@testable import HistoryKit

final class WeekStripTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1 // Sunday
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func completed(_ at: Date) -> SessionRecord {
        SessionRecord(routineID: UUID(), startedAt: at, completedAt: at)
    }

    func test_coversTheSevenDaysOfTheWeek_startingOnFirstWeekday() {
        // 2026-11-10 is a Tuesday; the Sunday-first week runs Nov 8–14.
        let strip = WeekStrip.forWeek(containing: date(2026, 11, 10), sessions: [], calendar: cal)
        XCTAssertEqual(strip.days.count, 7)
        XCTAssertEqual(strip.days.first?.date, cal.startOfDay(for: date(2026, 11, 8)))
        XCTAssertEqual(strip.days.last?.date, cal.startOfDay(for: date(2026, 11, 14)))
    }

    func test_marksToday() {
        let strip = WeekStrip.forWeek(containing: date(2026, 11, 10), sessions: [], calendar: cal)
        XCTAssertEqual(strip.days.filter(\.isToday).map(\.date), [cal.startOfDay(for: date(2026, 11, 10))])
    }

    func test_marksCompletedDays_andIgnoresOtherWeeksAndUnfinishedSessions() {
        let unfinished = SessionRecord(routineID: UUID(), startedAt: date(2026, 11, 12))
        let strip = WeekStrip.forWeek(
            containing: date(2026, 11, 10),
            sessions: [
                completed(date(2026, 11, 8)),
                completed(date(2026, 11, 9, hour: 7)),
                completed(date(2026, 11, 9, hour: 19)),  // same day twice counts once
                completed(date(2026, 11, 3)),            // previous week
                unfinished,
            ],
            calendar: cal
        )
        XCTAssertEqual(strip.completedCount, 2)
        XCTAssertFalse(strip.isTodayCompleted)
    }

    func test_isTodayCompleted_whenSessionFinishedToday() {
        let strip = WeekStrip.forWeek(
            containing: date(2026, 11, 10),
            sessions: [completed(date(2026, 11, 10, hour: 8))],
            calendar: cal
        )
        XCTAssertTrue(strip.isTodayCompleted)
    }
}
