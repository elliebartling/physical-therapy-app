import XCTest
import DataKit
@testable import HistoryKit

final class DayProgressTests: XCTestCase {
    private let calendar = Calendar.current
    private func day(_ d: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }

    func test_skipping_carriesOnFromWhatsDoneToday_untilTheDayIsComplete() {
        let bridges = UUID(), clams = UUID()
        let partial = SessionRecord(routineID: UUID(), startedAt: day(11, hour: 7), exerciseRecords: [
            ExerciseRecord(exerciseID: bridges, status: .completed, startedAt: day(11, hour: 7)),
            ExerciseRecord(exerciseID: clams, status: .skipped, startedAt: day(11, hour: 7)),
        ])
        let yesterday = SessionRecord(routineID: UUID(), startedAt: day(10), completedAt: day(10), exerciseRecords: [
            ExerciseRecord(exerciseID: clams, status: .completed, startedAt: day(10)),
        ])

        XCTAssertEqual(DayProgress.skipping(on: day(11, hour: 18), in: [partial, yesterday], calendar: calendar), [bridges])

        let finished = SessionRecord(routineID: UUID(), startedAt: day(11, hour: 12), completedAt: day(11, hour: 12))
        XCTAssertEqual(DayProgress.skipping(on: day(11, hour: 18), in: [partial, finished], calendar: calendar), [],
                       "once the day is complete, Start again runs it all")
    }

    func test_coversRequired_ignoresOptionalExercises() {
        let bridges = Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 3), restSeconds: 0, side: .both)
        let extra = Exercise(name: "Extra", target: .repsSets(reps: 10, sets: 1), restSeconds: 0, side: .both, isOptional: true)

        XCTAssertTrue(DayProgress.coversRequired([bridges, extra], done: [bridges.id]))
        XCTAssertFalse(DayProgress.coversRequired([bridges, extra], done: [extra.id]))
    }
}
