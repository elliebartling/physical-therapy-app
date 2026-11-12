import XCTest
import DataKit
@testable import HistoryKit

final class ProgressStatsTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }

    private func day(_ d: Int, month: Int = 11, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: d, hour: hour))!
    }

    private func complete(on date: Date, records: [ExerciseRecord] = []) -> SessionRecord {
        SessionRecord(routineID: UUID(), startedAt: date, completedAt: date, exerciseRecords: records)
    }

    // Wed 11 Nov 2026 is in the week starting Mon 9 Nov.
    private var today: Date { day(11, hour: 15) }

    func test_weeklyDays_countsDistinctDaysPerWeek_oldestFirst() {
        let sessions = [
            complete(on: day(9)), complete(on: day(9, hour: 18)), // same day twice → 1
            complete(on: day(10)),
            complete(on: day(3)),                                  // previous week
            SessionRecord(routineID: UUID(), startedAt: day(4)),   // partial: not counted
        ]

        let weeks = ProgressStats.weeklyDays(in: sessions, weeks: 3, today: today, calendar: calendar)

        XCTAssertEqual(weeks.map(\.days), [0, 1, 2])
        XCTAssertEqual(weeks.last?.weekStart, day(9, hour: 0))
        XCTAssertEqual(weeks.first?.weekStart, day(26, month: 10, hour: 0))
    }

    func test_weeklyDays_withNoWeeks_isEmpty() {
        XCTAssertEqual(ProgressStats.weeklyDays(in: [], weeks: 0, today: today, calendar: calendar), [])
    }

    func test_exerciseStats_countsDoneAndSkipped_andRemembersTheLatest() {
        let bridges = UUID(), clams = UUID()
        let sessions = [
            complete(on: day(3), records: [
                ExerciseRecord(exerciseID: bridges, status: .completed, startedAt: day(3), completedAt: day(3)),
                ExerciseRecord(exerciseID: clams, status: .skipped, startedAt: day(3)),
            ]),
            complete(on: day(10), records: [
                ExerciseRecord(exerciseID: bridges, status: .completed, startedAt: day(10), completedAt: day(10)),
                ExerciseRecord(exerciseID: clams, status: .completed, startedAt: day(10), completedAt: day(10)),
            ]),
        ]

        let stats = ProgressStats.exerciseStats(in: sessions)

        XCTAssertEqual(stats[bridges], ExerciseStats(completed: 2, skipped: 0, lastDone: day(10)))
        XCTAssertEqual(stats[clams], ExerciseStats(completed: 1, skipped: 1, lastDone: day(10)))
        XCTAssertEqual(stats[clams]?.completionRate, 0.5)
        XCTAssertNil(ExerciseStats().completionRate)
    }

    func test_completedDayCount_ignoresPartialsAndRepeats() {
        let sessions = [
            complete(on: day(9)), complete(on: day(9, hour: 20)), complete(on: day(10)),
            SessionRecord(routineID: UUID(), startedAt: day(11)),
        ]
        XCTAssertEqual(ProgressStats.completedDayCount(in: sessions, calendar: calendar), 2)
    }

    func test_exerciseStats_groupedBy_poolsRecordsAcrossIDs() {
        let phase1 = UUID(), phase2 = UUID(), other = UUID()
        let sessions = [
            complete(on: day(2), records: [ExerciseRecord(exerciseID: phase1, status: .completed, startedAt: day(2), completedAt: day(2))]),
            complete(on: day(9), records: [
                ExerciseRecord(exerciseID: phase2, status: .completed, startedAt: day(9), completedAt: day(9)),
                ExerciseRecord(exerciseID: other, status: .skipped, startedAt: day(9)),
            ]),
        ]

        let stats = ProgressStats.exerciseStats(in: sessions, groupedBy: { $0 == phase2 ? phase1 : $0 })

        XCTAssertEqual(stats[phase1], ExerciseStats(completed: 2, skipped: 0, lastDone: day(9)))
        XCTAssertNil(stats[phase2])
        XCTAssertEqual(stats[other], ExerciseStats(completed: 0, skipped: 1, lastDone: nil))
    }
}
