import XCTest
import SwiftData
import DataKit
import HistoryKit
@testable import UI

/// Stands in for Apple Health's workouts.
private final class FakeWorkoutReader: WorkoutReader, @unchecked Sendable {
    let isAvailable: Bool
    var workouts: [OtherWorkout] = []
    private(set) var requestedAccess = false

    init(isAvailable: Bool = true) { self.isAvailable = isAvailable }

    func requestReadAccess() async throws { requestedAccess = true }

    func workouts(from start: Date, to end: Date) async throws -> [OtherWorkout] {
        workouts.filter { $0.start >= start && $0.start <= end }.sorted { $0.start > $1.start }
    }
}

@MainActor
final class OtherWorkoutsUITests: XCTestCase {
    private var container: ModelContainer!
    private var routineRepo: RoutineRepository!
    private var sessionRepo: SessionRepository!
    private var routine: Routine!
    private var defaults: UserDefaults!
    private var suiteName = ""
    private var reader: FakeWorkoutReader!

    private let calendar = Calendar.current
    private let yoga = WorkoutActivity(id: 57, name: "Yoga", tag: "YOGA")
    private let running = WorkoutActivity(id: 37, name: "Running", tag: "RUN")

    private func day(_ d: Int, month: Int = 11, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: d, hour: hour))!
    }
    /// Wednesday afternoon.
    private var today: Date { day(11, hour: 15) }
    private var bridges: Exercise { routine.orderedExercises[0] }
    private var childsPose: Exercise { routine.orderedExercises[1] }
    private var figureFour: Exercise { routine.orderedExercises[2] }

    override func setUp() async throws {
        container = try ModelContainerFactory.inMemory()
        routineRepo = RoutineRepository(context: container.mainContext)
        sessionRepo = SessionRepository(context: container.mainContext)
        routine = Routine(name: "Hips", exercises: [
            Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both, order: 0),
            Exercise(name: "Child's pose", target: .timeSets(seconds: 30, sets: 1), restSeconds: 0, side: .both, order: 1),
            Exercise(name: "Figure-4", target: .timeSets(seconds: 30, sets: 2), restSeconds: 0, side: .alternating, order: 2),
        ])
        try routineRepo.save(routine)
        suiteName = "OtherWorkoutsUITests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        reader = FakeWorkoutReader()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        reader = nil; defaults = nil; routine = nil; sessionRepo = nil; routineRepo = nil; container = nil
    }

    // MARK: Helpers

    private func source(reads: Bool = true) -> OtherWorkoutsSource {
        HealthPreferences(readsWorkouts: reads).save(to: defaults)
        return OtherWorkoutsSource(reader: reader, defaults: defaults)
    }

    private func home(_ source: OtherWorkoutsSource) async -> HomeViewModel {
        let vm = HomeViewModel(routineRepo: routineRepo, sessionRepo: sessionRepo, otherWorkouts: source, today: today)
        await vm.refresh()
        return vm
    }

    private func progress(_ source: OtherWorkoutsSource) async -> ProgressViewModel {
        let vm = ProgressViewModel(routineRepo: routineRepo, sessionRepo: sessionRepo, defaults: defaults,
                                   otherWorkouts: source, today: today)
        vm.refresh()
        await vm.loadOtherWorkouts()
        return vm
    }

    @discardableResult
    private func addWorkout(_ activity: WorkoutActivity, at date: Date, minutes: Double = 45,
                            meters: Double? = nil) -> OtherWorkout {
        let workout = OtherWorkout(id: UUID(), activity: activity, start: date,
                                   end: date.addingTimeInterval(minutes * 60), distanceMeters: meters)
        reader.workouts.append(workout)
        return workout
    }

    private func yogaCovers(_ exercises: [Exercise], asksFirst: Bool = true, in source: OtherWorkoutsSource) {
        source.save(CoverageRule(activity: yoga, exerciseLineages: Set(exercises.map(\.lineageID)),
                                 minimumMinutes: 30, asksFirst: asksFirst))
    }

    // MARK: Today

    func test_aCoveringWorkout_isOffered_andCountingItCoversThoseExercises() async throws {
        let source = source()
        let workout = addWorkout(yoga, at: day(11, hour: 8))
        yogaCovers([childsPose, figureFour], in: source)
        let vm = await home(source)

        let offer = try XCTUnwrap(vm.offers.first)
        XCTAssertEqual(offer.workoutName, "Yoga")
        XCTAssertEqual(offer.minutes, 45)
        XCTAssertEqual(offer.exercises.map(\.name), ["Child's pose", "Figure-4"])

        await vm.count(offer)

        XCTAssertTrue(vm.offers.isEmpty)
        XCTAssertEqual(vm.rows.map(\.coveredBy), [nil, "Yoga", "Yoga"])
        XCTAssertEqual(vm.remainingCount, 1)
        XCTAssertFalse(vm.isDoneToday, "Bridges is still to do")
        let saved = try XCTUnwrap(sessionRepo.fetchAll().first { $0.coveringWorkoutID == workout.id })
        XCTAssertNil(saved.completedAt)
        XCTAssertEqual(saved.exerciseRecords.map(\.coveredBy), ["Yoga", "Yoga"])
        XCTAssertEqual(Set(saved.exerciseRecords.map(\.exerciseID)), [childsPose.id, figureFour.id])
    }

    func test_coveringWhatsLeft_makesItAFullDay() async throws {
        let source = source()
        try sessionRepo.insert(SessionRecord(routineID: routine.id, startedAt: day(11, hour: 7), exerciseRecords: [
            ExerciseRecord(exerciseID: bridges.id, status: .completed, startedAt: day(11, hour: 7)),
            ExerciseRecord(exerciseID: childsPose.id, status: .skipped, startedAt: day(11, hour: 7)),
            ExerciseRecord(exerciseID: figureFour.id, status: .skipped, startedAt: day(11, hour: 7)),
        ]))
        addWorkout(yoga, at: day(11, hour: 8))
        yogaCovers([childsPose, figureFour], in: source)
        let vm = await home(source)

        await vm.count(try XCTUnwrap(vm.offers.first))

        XCTAssertTrue(vm.isDoneToday)
        XCTAssertEqual(vm.streak, 1)
        XCTAssertEqual(vm.remainingCount, 1, "Bridges was done in Mend, not covered")
    }

    func test_notToday_stopsOfferingThatWorkout() async throws {
        let source = source()
        addWorkout(yoga, at: day(11, hour: 8))
        yogaCovers([childsPose], in: source)
        let vm = await home(source)

        vm.dismiss(try XCTUnwrap(vm.offers.first))

        XCTAssertTrue(vm.offers.isEmpty)
        let later = await home(source)
        XCTAssertTrue(later.offers.isEmpty)
        XCTAssertTrue(try sessionRepo.fetchAll().isEmpty)
    }

    func test_aWorkoutSetNotToAsk_countsOnItsOwn_once() async throws {
        let source = source()
        addWorkout(yoga, at: day(11, hour: 8))
        yogaCovers([childsPose], asksFirst: false, in: source)

        let vm = await home(source)
        await vm.refresh()

        XCTAssertTrue(vm.offers.isEmpty)
        XCTAssertEqual(vm.rows.map(\.coveredBy), [nil, "Yoga", nil])
        XCTAssertEqual(try sessionRepo.fetchAll().count, 1)
    }

    func test_nothingIsOffered_whenReadingIsOff_orTheWorkoutIsTooShort() async throws {
        addWorkout(yoga, at: day(11, hour: 8))
        let off = source(reads: false)
        yogaCovers([childsPose], in: off)
        let vm = await home(off)
        XCTAssertTrue(vm.offers.isEmpty)
        XCTAssertTrue(vm.week.days.allSatisfy { $0.otherWorkout == nil })

        reader.workouts = []
        addWorkout(yoga, at: day(11, hour: 8), minutes: 15)
        let short = await home(source())
        XCTAssertTrue(short.offers.isEmpty, "shorter than the rule's 30 minutes")
    }

    func test_weekStrip_tagsDaysWithOtherWorkouts() async throws {
        addWorkout(running, at: day(10, hour: 7), minutes: 30)
        let vm = await home(source())

        let tuesday = try XCTUnwrap(vm.week.days.first { calendar.isDate($0.date, inSameDayAs: day(10)) })
        XCTAssertEqual(tuesday.otherWorkout, "RUN")
    }

    // MARK: Progress

    func test_progress_listsOtherWorkouts_andWhatTheyCover() async throws {
        let source = source()
        for d in [2, 5, 9] { addWorkout(running, at: day(d, hour: 7), minutes: 30, meters: 5000) }
        addWorkout(yoga, at: day(10, hour: 8))
        yogaCovers([childsPose, figureFour], in: source)
        try sessionRepo.insert(SessionRecord(routineID: routine.id, startedAt: day(9), completedAt: day(9)))

        let vm = await progress(source)

        XCTAssertEqual(vm.activities.map(\.activity.name), ["Running", "Yoga"])
        XCTAssertEqual(vm.activities.map(\.covers), [0, 2])
        XCTAssertTrue(vm.heatmap.flatMap(\.others).contains(true))
        let summary = vm.visitSummary()
        XCTAssertTrue(summary.contains("OTHER WORKOUTS (FROM APPLE HEALTH)"))
        XCTAssertTrue(summary.contains("• Running: 3 times, 1 h 30 min"))
        XCTAssertTrue(summary.contains("• Yoga: 1 time, 45 min"))
    }

    func test_progress_morePainTheDayAfterARun_isWorthTellingYourPT() async throws {
        let source = source()
        for d in [2, 5, 9] { addWorkout(running, at: day(d, hour: 7), minutes: 30) }
        let readings: [(Date, Int)] = [
            (day(3), 5), (day(5, hour: 18), 4), (day(10), 4),       // within a day of a run
            (day(28, month: 10), 2), (day(1), 1), (day(7), 2),      // not
        ]
        for (date, pain) in readings {
            let session = SessionRecord(routineID: routine.id, startedAt: date, completedAt: date.addingTimeInterval(600))
            session.painLevel = pain
            try sessionRepo.insert(session)
        }

        let vm = await progress(source)

        let insight = try XCTUnwrap(vm.insights.first { $0.id.hasPrefix("after-") })
        XCTAssertEqual(insight.title, "Running — more pain after")
        XCTAssertEqual(insight.detail, "Pain after sessions averaged 4.3 within a day of running, 1.7 otherwise (3 sessions).")
        XCTAssertEqual(vm.activities.first?.nextDayPain?.isHigher, true)
    }

    func test_progress_showsWhereAnotherWorkoutStoodIn() async throws {
        let source = source()
        for d in [6, 9] {
            let records = [childsPose, figureFour].map { exercise in
                let record = ExerciseRecord(exerciseID: exercise.id, status: .completed, startedAt: day(d), completedAt: day(d))
                record.coveredBy = "Yoga"
                return record
            }
            let session = SessionRecord(routineID: routine.id, startedAt: day(d), exerciseRecords: records)
            session.coveringWorkoutID = UUID()
            try sessionRepo.insert(session)
        }

        let vm = await progress(source)

        let insight = try XCTUnwrap(vm.insights.first { $0.id == "covers-Yoga" })
        XCTAssertEqual(insight.detail, "Yoga counted for Child's pose and Figure-4 2 times in the last four weeks. "
                       + "Worth checking with your PT that it covers them.")
        XCTAssertEqual(vm.marks(forExercise: childsPose.id, count: 12), [.covered, .covered])
        XCTAssertEqual(vm.entries(forExercise: figureFour.id).first?.coveredBy, "Yoga")
        XCTAssertEqual(vm.months.first?.sessions.first?.items.first?.coveredBy, "Yoga")
    }

    // MARK: Settings

    func test_settings_turningOnOtherWorkouts_asksHealth_andIsRemembered() async {
        let settings = SettingsViewModel(workoutReader: reader, defaults: defaults)

        await settings.setReadsWorkouts(true)

        XCTAssertTrue(settings.readsWorkouts)
        XCTAssertTrue(reader.requestedAccess)
        XCTAssertTrue(HealthPreferences.load(from: defaults).readsWorkouts)

        await settings.setReadsWorkouts(false)
        XCTAssertFalse(HealthPreferences.load(from: defaults).readsWorkouts)
    }

    func test_settings_otherWorkouts_stayOffWithoutHealth() async {
        let settings = SettingsViewModel(workoutReader: FakeWorkoutReader(isAvailable: false), defaults: defaults)

        await settings.setReadsWorkouts(true)

        XCTAssertFalse(settings.readsWorkouts)
        XCTAssertNotNil(settings.readMessage)
    }

    func test_ruleEditor_savesEachChange_andCanStopCounting() {
        let source = source()
        let exercises = CoverableExercise.all(in: routine)
        let editor = CoverageRuleEditorModel(activity: yoga, exercises: exercises, source: source)

        editor.toggle(exercises[1])
        editor.minimumMinutes = 2
        editor.asksFirst = false

        let saved = source.rule(for: yoga.id)
        XCTAssertEqual(saved?.exerciseLineages, [childsPose.lineageID])
        XCTAssertEqual(saved?.minimumMinutes, 5, "at least five minutes")
        XCTAssertEqual(saved?.asksFirst, false)

        editor.remove()
        XCTAssertNil(source.rule(for: yoga.id))
        XCTAssertFalse(editor.isSaved)
    }

    // MARK: Counting toward the goal and streak

    func test_otherWorkoutDays_countTowardTheStreakAndTheWeek() async throws {
        addWorkout(running, at: day(9, hour: 7), minutes: 30)
        addWorkout(running, at: day(10, hour: 7), minutes: 30)
        addWorkout(yoga, at: day(8, hour: 7), minutes: 5)      // too short to count

        let vm = await home(source())

        XCTAssertEqual(vm.streak, 2, "Monday and Tuesday")
        XCTAssertEqual(vm.headline, "2 active days this week.")
        XCTAssertFalse(vm.isDoneToday, "today still needs PT")
        let tuesday = try XCTUnwrap(vm.week.days.first { calendar.isDate($0.date, inSameDayAs: day(10)) })
        XCTAssertTrue(tuesday.countsOtherWorkout)
    }

    func test_otherWorkoutDays_canBeLeftOutOfTheStreak() async throws {
        addWorkout(running, at: day(10, hour: 7), minutes: 30)
        let source = source()
        HealthPreferences(readsWorkouts: true, countsTowardGoal: false).save(to: defaults)

        let vm = await home(source)

        XCTAssertEqual(vm.streak, 0)
        XCTAssertEqual(vm.headline, "Ready when you are.")
        XCTAssertEqual(vm.week.days.first { calendar.isDate($0.date, inSameDayAs: day(10)) }?.otherWorkout, "RUN")
    }

    func test_aPartlyDoneDay_showsAsPartial() async throws {
        try sessionRepo.insert(SessionRecord(routineID: routine.id, startedAt: day(10), exerciseRecords: [
            ExerciseRecord(exerciseID: bridges.id, status: .completed, startedAt: day(10)),
        ]))

        let vm = await home(source())

        let tuesday = try XCTUnwrap(vm.week.days.first { calendar.isDate($0.date, inSameDayAs: day(10)) })
        XCTAssertTrue(tuesday.isPartial)
        XCTAssertFalse(tuesday.isActive)
    }

    func test_progress_countsOtherWorkoutDaysTowardTheGoal_andSaysSoForYourPT() async throws {
        try sessionRepo.insert(SessionRecord(routineID: routine.id, startedAt: day(9), completedAt: day(9)))
        addWorkout(running, at: day(10, hour: 7), minutes: 30)

        let vm = await progress(source())

        XCTAssertEqual(vm.daysThisWeek, 2)
        XCTAssertEqual(vm.sessionDays, 1)
        XCTAssertTrue(vm.heatmap.flatMap(\.days).contains(.otherWorkout))
        let summary = vm.visitSummary()
        XCTAssertTrue(summary.contains("• 1 day with a full session"))
        XCTAssertTrue(summary.contains("• 1 more day with another workout, counted toward the goal"))
    }

    func test_settings_countingTowardTheGoal_isOnUntilTurnedOff() {
        let settings = SettingsViewModel(workoutReader: reader, defaults: defaults)
        XCTAssertTrue(settings.workoutsCountTowardGoal)

        settings.workoutsCountTowardGoal = false

        XCTAssertFalse(HealthPreferences.load(from: defaults).countsTowardGoal)
    }
}
