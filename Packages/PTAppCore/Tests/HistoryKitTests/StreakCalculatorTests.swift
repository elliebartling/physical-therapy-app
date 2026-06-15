import XCTest
import DataKit
@testable import HistoryKit

final class StreakCalculatorTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func day(_ offset: Int, from anchor: Date) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: anchor))!
    }
    private func session(completedAt: Date) -> SessionRecord {
        let s = SessionRecord(routineID: UUID(), startedAt: completedAt)
        s.completedAt = completedAt
        return s
    }

    func test_emptyHistory_returnsZero() {
        XCTAssertEqual(StreakCalculator.currentStreak(in: [], today: .now, calendar: cal), 0)
    }

    func test_completedToday_returnsOne() {
        let today = day(0, from: .now)
        XCTAssertEqual(
            StreakCalculator.currentStreak(in: [session(completedAt: today)], today: today, calendar: cal),
            1
        )
    }

    func test_completedYesterdayButNotToday_returnsOne() {
        let today = day(0, from: .now)
        let yesterday = day(-1, from: today)
        XCTAssertEqual(
            StreakCalculator.currentStreak(in: [session(completedAt: yesterday)], today: today, calendar: cal),
            1
        )
    }

    func test_gapBreaksStreak() {
        let today = day(0, from: .now)
        let sessions = [
            session(completedAt: today),
            session(completedAt: day(-1, from: today)),
            session(completedAt: day(-3, from: today)),
        ]
        XCTAssertEqual(StreakCalculator.currentStreak(in: sessions, today: today, calendar: cal), 2)
    }

    func test_multipleSessionsOnSameDay_countOnce() {
        let today = day(0, from: .now)
        let sessions = [
            session(completedAt: today),
            session(completedAt: today.addingTimeInterval(60)),
            session(completedAt: day(-1, from: today)),
        ]
        XCTAssertEqual(StreakCalculator.currentStreak(in: sessions, today: today, calendar: cal), 2)
    }

    func test_sessionWithoutCompletedAt_isIgnored() {
        let today = day(0, from: .now)
        let partial = SessionRecord(routineID: UUID(), startedAt: today)
        XCTAssertEqual(StreakCalculator.currentStreak(in: [partial], today: today, calendar: cal), 0)
    }
}
