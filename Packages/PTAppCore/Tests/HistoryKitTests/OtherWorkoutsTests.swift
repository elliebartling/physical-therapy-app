import XCTest
import DataKit
@testable import HistoryKit

final class OtherWorkoutsTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }

    private func day(_ d: Int, month: Int = 11, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: d, hour: hour))!
    }

    private let running = WorkoutActivity(id: 37, name: "Running", tag: "RUN")
    private let yoga = WorkoutActivity(id: 57, name: "Yoga", tag: "YOGA")

    private func workout(_ activity: WorkoutActivity, on date: Date, minutes: Double = 30,
                         meters: Double? = nil) -> OtherWorkout {
        OtherWorkout(id: UUID(), activity: activity, start: date, end: date.addingTimeInterval(minutes * 60),
                     distanceMeters: meters)
    }

    func test_rule_appliesToLongEnoughWorkoutsOfItsKind_thatCoverSomething() {
        let rule = CoverageRule(activity: yoga, exerciseLineages: [UUID()], minimumMinutes: 30)

        XCTAssertTrue(rule.applies(to: workout(yoga, on: day(10), minutes: 45)))
        XCTAssertFalse(rule.applies(to: workout(yoga, on: day(10), minutes: 20)), "too short")
        XCTAssertFalse(rule.applies(to: workout(running, on: day(10), minutes: 45)), "another kind")
        XCTAssertFalse(CoverageRule(activity: yoga).applies(to: workout(yoga, on: day(10), minutes: 45)),
                       "covers nothing")
    }

    func test_coveredAndDoneExercises_onADay() {
        let stretch = UUID(), bridges = UUID(), clams = UUID()
        let covered = ExerciseRecord(exerciseID: stretch, status: .completed, startedAt: day(10), completedAt: day(10))
        covered.coveredBy = "Yoga"
        let sessions = [
            SessionRecord(routineID: UUID(), startedAt: day(10), exerciseRecords: [covered]),
            SessionRecord(routineID: UUID(), startedAt: day(10, hour: 18), exerciseRecords: [
                ExerciseRecord(exerciseID: bridges, status: .completed, startedAt: day(10, hour: 18)),
                ExerciseRecord(exerciseID: clams, status: .skipped, startedAt: day(10, hour: 18)),
            ]),
            SessionRecord(routineID: UUID(), startedAt: day(9), exerciseRecords: [
                ExerciseRecord(exerciseID: clams, status: .completed, startedAt: day(9)),
            ]),
        ]

        XCTAssertEqual(OtherWorkoutStats.coveredExercises(on: day(10, hour: 20), in: sessions, calendar: calendar),
                       [stretch: "Yoga"])
        XCTAssertEqual(OtherWorkoutStats.doneExercises(on: day(10), in: sessions, calendar: calendar), [stretch, bridges])
    }

    func test_summaries_totalEachKind_mostFrequentFirst() {
        let workouts = [workout(running, on: day(2), minutes: 30, meters: 5000),
                        workout(yoga, on: day(3), minutes: 45),
                        workout(running, on: day(5), minutes: 40, meters: 6500)]

        let summaries = OtherWorkoutStats.summaries(of: workouts)

        XCTAssertEqual(summaries, [
            ActivitySummary(activity: running, count: 2, minutes: 70, distanceMeters: 11500),
            ActivitySummary(activity: yoga, count: 1, minutes: 45, distanceMeters: nil),
        ])
    }

    func test_nextDayPain_comparesSessionsWithinADayOfTheWorkout() {
        let runs = [day(2, hour: 7), day(5, hour: 7), day(9, hour: 7)].map { workout(running, on: $0) }
        let points = [
            PainPoint(date: day(3, hour: 9), level: 5),   // the morning after a run
            PainPoint(date: day(5, hour: 18), level: 4),  // the evening of one
            PainPoint(date: day(10, hour: 9), level: 4),
            PainPoint(date: day(1), level: 2),
            PainPoint(date: day(7), level: 1),
            PainPoint(date: day(12), level: 2),           // three days later: not after
        ]

        let pain = OtherWorkoutStats.nextDayPain(points: points, workouts: runs, activityID: running.id)

        XCTAssertEqual(pain?.count, 3)
        XCTAssertEqual(pain?.after ?? 0, 13.0 / 3, accuracy: 0.001)
        XCTAssertEqual(pain?.otherwise ?? 0, 5.0 / 3, accuracy: 0.001)
        XCTAssertEqual(pain?.isHigher, true)
    }

    func test_nextDayPain_needsThreeEachSide_andAPointOfDifference() {
        let runs = [day(2, hour: 7), day(5, hour: 7)].map { workout(running, on: $0) }
        let few = [PainPoint(date: day(3), level: 5), PainPoint(date: day(6), level: 5),
                   PainPoint(date: day(10), level: 1), PainPoint(date: day(12), level: 1), PainPoint(date: day(14), level: 1)]
        XCTAssertNil(OtherWorkoutStats.nextDayPain(points: few, workouts: runs, activityID: running.id))

        let moreRuns = runs + [workout(running, on: day(8, hour: 7))]
        let flat = [PainPoint(date: day(3), level: 3), PainPoint(date: day(6), level: 3), PainPoint(date: day(9), level: 3),
                    PainPoint(date: day(11), level: 3), PainPoint(date: day(13), level: 2), PainPoint(date: day(15), level: 3)]
        XCTAssertNil(OtherWorkoutStats.nextDayPain(points: flat, workouts: moreRuns, activityID: running.id))
    }

    func test_heatmapAndWeekStrip_markDaysWithOtherWorkouts() {
        let today = day(11, hour: 15)  // Wednesday
        let workouts = [workout(running, on: day(9, hour: 7), minutes: 30),
                        workout(yoga, on: day(9, hour: 18), minutes: 60),
                        workout(running, on: day(4, hour: 7))]

        let heatmap = ProgressStats.heatmap(in: [], weeks: 2, today: today,
                                            otherWorkoutDays: OtherWorkoutStats.days(of: workouts, calendar: calendar),
                                            calendar: calendar)
        XCTAssertEqual(heatmap[0].others, [false, false, true, false, false, false, false])
        XCTAssertEqual(heatmap[1].others, [true, false, false, false, false, false, false])

        let week = WeekStrip.forWeek(containing: today, sessions: [], otherWorkouts: workouts, calendar: calendar)
        XCTAssertEqual(week.days.map(\.otherWorkout), ["YOGA", nil, nil, nil, nil, nil, nil],
                       "the longest workout that day gives the tag")
    }

    // MARK: Counting toward the goal and streak

    func test_countingDays_needTenMinutes() {
        let workouts = [workout(running, on: day(9), minutes: 25), workout(yoga, on: day(10), minutes: 8)]
        XCTAssertEqual(OtherWorkoutStats.countingDays(of: workouts, calendar: calendar), [day(9, hour: 0)])
    }

    func test_countedDays_joinTheStreakTheWeekAndTheHeatmap() {
        let today = day(11, hour: 15)  // Wednesday
        let session = SessionRecord(routineID: UUID(), startedAt: day(11), completedAt: day(11))
        let extra: Set<Date> = [day(9, hour: 0), day(10, hour: 0), day(11, hour: 0)]

        XCTAssertEqual(StreakCalculator.currentStreak(in: [session], today: today, calendar: calendar), 1)
        XCTAssertEqual(StreakCalculator.currentStreak(in: [session], today: today, calendar: calendar, extraDays: extra), 3)
        XCTAssertEqual(ProgressStats.weeklyDays(in: [session], weeks: 1, today: today, calendar: calendar,
                                                extraDays: extra).map(\.days), [3], "a day with both counts once")
        XCTAssertEqual(ProgressStats.longestStreak(in: [], from: day(1), through: today, calendar: calendar,
                                                   extraDays: extra), 3)

        let heatmap = ProgressStats.heatmap(in: [session], weeks: 1, today: today, countedDays: extra, calendar: calendar)
        XCTAssertEqual(heatmap[0].days, [.otherWorkout, .otherWorkout, .done, .future, .future, .future, .future])
    }

    func test_heatmap_aPartlyDoneDay_staysPartial_whenAWorkoutAlsoCounted() {
        let today = day(11, hour: 15)  // Wednesday
        let started = SessionRecord(routineID: UUID(), startedAt: day(10))  // never finished
        let workoutDays: Set<Date> = [day(9, hour: 0), day(10, hour: 0)]

        let heatmap = ProgressStats.heatmap(in: [started], weeks: 1, today: today, otherWorkoutDays: workoutDays,
                                            countedDays: workoutDays, calendar: calendar)

        XCTAssertEqual(heatmap[0].days, [.otherWorkout, .partial, .rest, .future, .future, .future, .future],
                       "the PT done that day still shows; the workout has its own mark")
        XCTAssertEqual(heatmap[0].others, [true, true, false, false, false, false, false])
    }

    func test_weekStrip_marksPartialDays_andCountedWorkouts() {
        let today = day(11, hour: 15)
        let sessions = [SessionRecord(routineID: UUID(), startedAt: day(9))]   // started, not finished
        let workouts = [workout(running, on: day(10, hour: 7), minutes: 30)]

        let counting = WeekStrip.forWeek(containing: today, sessions: sessions, otherWorkouts: workouts,
                                         countingOtherWorkouts: true, calendar: calendar)
        XCTAssertEqual(counting.days.map(\.isPartial), [true, false, false, false, false, false, false])
        XCTAssertEqual(counting.days.map(\.countsOtherWorkout), [false, true, false, false, false, false, false])
        XCTAssertEqual(counting.activeCount, 1)
        XCTAssertEqual(counting.completedCount, 0)

        let notCounting = WeekStrip.forWeek(containing: today, sessions: sessions, otherWorkouts: workouts,
                                            calendar: calendar)
        XCTAssertEqual(notCounting.activeCount, 0)
        XCTAssertEqual(notCounting.days[1].otherWorkout, "RUN", "still tagged")
    }
}
