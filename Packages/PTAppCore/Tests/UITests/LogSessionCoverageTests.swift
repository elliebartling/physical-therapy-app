import XCTest
import SwiftData
import DataKit
import HistoryKit
@testable import UI

/// Stands in for Apple Health's workouts.
private final class StubWorkoutReader: WorkoutReader, @unchecked Sendable {
    let isAvailable = true
    var workouts: [OtherWorkout] = []

    func requestReadAccess() async throws {}

    func workouts(from start: Date, to end: Date) async throws -> [OtherWorkout] {
        workouts.filter { $0.start >= start && $0.start < end }
    }
}

/// Records what would be saved to Apple Health.
private actor RecordingWorkoutStore: WorkoutStore {
    nonisolated let isAvailable = true
    private(set) var samples: [WorkoutSample] = []
    func requestAccess() async throws -> Bool { true }
    func save(_ sample: WorkoutSample) async throws { samples.append(sample) }
}

@MainActor
final class LogSessionCoverageTests: XCTestCase {
    private var container: ModelContainer!
    private var sessionRepo: SessionRepository!
    private var routine: Routine!
    private var defaults: UserDefaults!
    private var suiteName = ""
    private var reader: StubWorkoutReader!
    private var source: OtherWorkoutsSource!

    private let calendar = Calendar.current
    private let yoga = WorkoutActivity(id: 57, name: "Yoga", tag: "YOGA")
    private let running = WorkoutActivity(id: 37, name: "Running", tag: "RUN")

    private func day(_ d: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }
    private var now: Date { day(11, hour: 15) }
    private var bridges: Exercise { routine.orderedExercises[0] }
    private var childsPose: Exercise { routine.orderedExercises[1] }
    private var figureFour: Exercise { routine.orderedExercises[2] }

    override func setUp() async throws {
        container = try ModelContainerFactory.inMemory()
        sessionRepo = SessionRepository(context: container.mainContext)
        routine = Routine(name: "Hips", exercises: [
            Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both, order: 0),
            Exercise(name: "Child's pose", target: .timeSets(seconds: 30, sets: 1), restSeconds: 0, side: .both, order: 1),
            Exercise(name: "Figure-4", target: .timeSets(seconds: 30, sets: 2), restSeconds: 0, side: .alternating, order: 2),
        ])
        try RoutineRepository(context: container.mainContext).save(routine)
        suiteName = "LogSessionCoverageTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        HealthPreferences(readsWorkouts: true).save(to: defaults)
        reader = StubWorkoutReader()
        source = OtherWorkoutsSource(reader: reader, defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        source = nil; reader = nil; defaults = nil; routine = nil; sessionRepo = nil; container = nil
    }

    @discardableResult
    private func addWorkout(_ activity: WorkoutActivity, at date: Date, minutes: Double = 45) -> OtherWorkout {
        let workout = OtherWorkout(id: UUID(), activity: activity, start: date, end: date.addingTimeInterval(minutes * 60))
        reader.workouts.append(workout)
        return workout
    }

    private func yogaCovers(_ exercises: [Exercise]) {
        source.save(CoverageRule(activity: yoga, exerciseLineages: Set(exercises.map(\.lineageID)), minimumMinutes: 30))
    }

    private func log(on date: Date, health: HealthRecorder? = nil) async -> LogSessionViewModel {
        let vm = LogSessionViewModel(routine: routine, sessionRepo: sessionRepo, date: date, now: now,
                                     health: health, otherWorkouts: source)
        await vm.loadWorkouts()
        return vm
    }

    func test_anEarlierDaysWorkout_countsForWhatItCovers() async throws {
        let workout = addWorkout(yoga, at: day(9, hour: 18))
        yogaCovers([childsPose, figureFour])

        let vm = await log(on: day(9))

        XCTAssertEqual(vm.workouts.map(\.name), ["Yoga"])
        XCTAssertEqual(vm.workouts.first?.isCounted, true, "set to cover exercises, so it starts counted")
        XCTAssertEqual(vm.items.map(\.coveredBy), [nil, "Yoga", "Yoga"])
        XCTAssertEqual(vm.coveredNames(for: try XCTUnwrap(vm.workouts.first)), ["Child's pose", "Figure-4"])

        XCTAssertTrue(vm.save())

        let saved = try XCTUnwrap(sessionRepo.fetchAll().first)
        XCTAssertEqual(saved.coveringWorkoutID, workout.id)
        XCTAssertNotNil(saved.completedAt, "everything was checked")
        XCTAssertTrue(calendar.isDate(saved.startedAt, inSameDayAs: day(9)))
        let byExercise = Dictionary(uniqueKeysWithValues: saved.exerciseRecords.map { ($0.exerciseID, $0.coveredBy) })
        XCTAssertEqual(byExercise[bridges.id], .some(nil))
        XCTAssertEqual(byExercise[childsPose.id], "Yoga")
    }

    func test_notCountingIt_orUncheckingAnExercise_dropsTheCoverage() async throws {
        addWorkout(yoga, at: day(9, hour: 18))
        yogaCovers([childsPose, figureFour])
        let vm = await log(on: day(9))
        let option = try XCTUnwrap(vm.workouts.first)

        vm.setDone(false, for: figureFour.id)
        XCTAssertEqual(vm.items.map(\.coveredBy), [nil, "Yoga", nil])

        vm.setCounted(false, for: option.id)
        XCTAssertEqual(vm.items.map(\.coveredBy), [nil, nil, nil])
        XCTAssertTrue(vm.save())
        XCTAssertNil(try sessionRepo.fetchAll().first?.coveringWorkoutID)
    }

    func test_aWorkoutWithNothingSet_canBeToldWhatItCovers() async throws {
        addWorkout(running, at: day(9, hour: 7), minutes: 30)
        let vm = await log(on: day(9))
        let option = try XCTUnwrap(vm.workouts.first)
        XCTAssertTrue(option.covers.isEmpty)
        XCTAssertFalse(option.isCounted)

        source.save(CoverageRule(activity: running, exerciseLineages: [bridges.lineageID]))
        vm.refreshRules()

        XCTAssertEqual(vm.workouts.first?.covers, [bridges.id])
        XCTAssertEqual(vm.workouts.first?.isCounted, true)
        XCTAssertEqual(vm.items.first?.coveredBy, "Running")
    }

    func test_onlyThatDaysUncountedWorkoutsShowUp() async throws {
        let counted = addWorkout(yoga, at: day(9, hour: 8))
        addWorkout(yoga, at: day(10, hour: 8))
        yogaCovers([childsPose])
        let earlier = SessionRecord(routineID: routine.id, startedAt: day(9, hour: 9))
        earlier.coveringWorkoutID = counted.id
        try sessionRepo.insert(earlier)

        let vm = await log(on: day(9))
        XCTAssertTrue(vm.workouts.isEmpty, "the 9th's yoga was already counted, and the 10th's is another day")

        vm.date = day(10)
        await vm.loadWorkouts()
        XCTAssertEqual(vm.workouts.count, 1)
    }

    func test_coveredExercises_areNotSavedToHealthAgain() async throws {
        addWorkout(yoga, at: day(9, hour: 18))
        yogaCovers([childsPose, figureFour])
        let store = RecordingWorkoutStore()
        let health = HealthRecorder(store: store, preferences: { HealthPreferences(isEnabled: true) })

        let onlyCovered = await log(on: day(9), health: health)
        onlyCovered.setDone(false, for: bridges.id)
        XCTAssertTrue(onlyCovered.save())
        await onlyCovered.healthSave?.value
        let afterCoveredOnly = await store.samples
        XCTAssertTrue(afterCoveredOnly.isEmpty, "the yoga is already in Health")

        reader.workouts = []
        let mixed = await log(on: day(8), health: health)
        XCTAssertTrue(mixed.save())
        await mixed.healthSave?.value
        let samples = await store.samples
        XCTAssertEqual(samples.count, 1)
    }
}
