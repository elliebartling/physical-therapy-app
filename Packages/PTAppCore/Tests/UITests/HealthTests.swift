import XCTest
import SwiftData
import DataKit
import SessionKit
@testable import UI

/// Stands in for Apple Health.
private actor FakeWorkoutStore: WorkoutStore {
    nonisolated let isAvailable: Bool
    private let grantsAccess: Bool
    private(set) var samples: [WorkoutSample] = []

    init(isAvailable: Bool = true, grantsAccess: Bool = true) {
        self.isAvailable = isAvailable
        self.grantsAccess = grantsAccess
    }

    func requestAccess() async throws -> Bool { grantsAccess }
    func save(_ sample: WorkoutSample) async throws { samples.append(sample) }
}

@MainActor
final class HealthTests: XCTestCase {
    private var container: ModelContainer!
    private var sessionRepo: SessionRepository!

    override func setUp() async throws {
        container = try ModelContainerFactory.inMemory()
        sessionRepo = SessionRepository(context: container.mainContext)
    }

    override func tearDown() async throws {
        sessionRepo = nil; container = nil
    }

    private func recorder(_ store: FakeWorkoutStore, enabled: Bool, kind: HealthWorkoutKind = .recovery) -> HealthRecorder {
        HealthRecorder(store: store, preferences: { HealthPreferences(isEnabled: enabled, kind: kind) })
    }

    private func knee() -> Routine {
        Routine(name: "Knee", exercises: [
            Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both, order: 0),
            Exercise(name: "Wall sit", target: .timeSets(seconds: 30, sets: 3), restSeconds: 30, side: .both, order: 1),
        ])
    }

    // MARK: Guided sessions

    func test_finishedSession_isSavedAsTheChosenWorkoutKind() async throws {
        let store = FakeWorkoutStore()
        let routine = Routine(name: "T", exercises: [
            Exercise(name: "Plank", target: .timeSets(seconds: 1, sets: 1), restSeconds: 0, side: .both, order: 0)
        ])
        let vm = SessionViewModel(routine: routine, sessionRepo: sessionRepo, clock: TestClock(),
                                  audio: nil, haptics: nil, health: recorder(store, enabled: true, kind: .pilates))
        await vm.run()
        await vm.healthSave?.value

        let samples = await store.samples
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.kind, .pilates)
        XCTAssertEqual(samples.first?.wasLoggedLater, false)
    }

    func test_healthTurnedOff_savesNothing() async throws {
        let store = FakeWorkoutStore()
        let routine = Routine(name: "T", exercises: [
            Exercise(name: "Plank", target: .timeSets(seconds: 1, sets: 1), restSeconds: 0, side: .both, order: 0)
        ])
        let vm = SessionViewModel(routine: routine, sessionRepo: sessionRepo, clock: TestClock(),
                                  audio: nil, haptics: nil, health: recorder(store, enabled: false))
        await vm.run()
        await vm.healthSave?.value

        let samples = await store.samples
        XCTAssertTrue(samples.isEmpty)
        XCTAssertEqual(try sessionRepo.fetchAll().count, 1, "the session itself is still saved in Mend")
    }

    func test_endingBeforeAnyExercise_savesNothingToHealth() async throws {
        let store = FakeWorkoutStore()
        let vm = SessionViewModel(routine: knee(), sessionRepo: sessionRepo, clock: TestClock(),
                                  audio: nil, haptics: nil, health: recorder(store, enabled: true))
        vm.endEarly()
        await vm.healthSave?.value

        let samples = await store.samples
        XCTAssertTrue(samples.isEmpty)
    }

    func test_healthSave_afterEndingEarly_doesNotTouchTheSessionOnceItsStoreIsGone() async throws {
        let store = FakeWorkoutStore()
        var local: ModelContainer? = try ModelContainerFactory.inMemory()
        let repo = SessionRepository(context: try XCTUnwrap(local).mainContext)
        let routine = Routine(name: "T", exercises: [
            Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 1), restSeconds: 0, side: .both, order: 0),
            Exercise(name: "Clams", target: .repsSets(reps: 10, sets: 1), restSeconds: 0, side: .both, order: 1),
        ])
        let vm = SessionViewModel(routine: routine, sessionRepo: repo, clock: TestClock(),
                                  audio: nil, haptics: nil, health: recorder(store, enabled: true))
        let run = Task { await vm.run() }
        defer { run.cancel() }
        try await Task.sleep(nanoseconds: 50_000_000)
        await vm.completeCurrentSet()   // Bridges done; the session waits on Clams
        try await Task.sleep(nanoseconds: 50_000_000)

        vm.endEarly()
        local = nil   // the store goes away before the Health save gets to run
        await vm.healthSave?.value

        let samples = await store.samples
        XCTAssertEqual(samples.count, 1)
    }

    // MARK: Logged sessions

    func test_loggedSession_isSavedAsEnteredByThePerson_sizedToWhatWasDone() async throws {
        let store = FakeWorkoutStore()
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 15))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let vm = LogSessionViewModel(routine: knee(), sessionRepo: sessionRepo, date: yesterday, now: now,
                                     health: recorder(store, enabled: true, kind: .flexibility))
        vm.items[1].isDone = false   // only bridges: 3×10 at 3s a rep + 2 rests of 30s = 150s → 3 min

        XCTAssertTrue(vm.save())
        await vm.healthSave?.value

        let samples = await store.samples
        let sample = try XCTUnwrap(samples.first)
        XCTAssertEqual(sample.kind, .flexibility)
        XCTAssertTrue(sample.wasLoggedLater)
        XCTAssertTrue(calendar.isDate(sample.end, inSameDayAs: yesterday))
        XCTAssertEqual(sample.end.timeIntervalSince(sample.start), 180, accuracy: 0.001)
    }

    func test_loggingToday_neverEndsInTheFuture() async throws {
        let store = FakeWorkoutStore()
        let now = Date.now
        let vm = LogSessionViewModel(routine: knee(), sessionRepo: sessionRepo, date: now, now: now,
                                     health: recorder(store, enabled: true))
        XCTAssertTrue(vm.save())
        await vm.healthSave?.value

        let samples = await store.samples
        let sample = try XCTUnwrap(samples.first)
        XCTAssertLessThanOrEqual(sample.end, now)
    }

    // MARK: Settings

    private func freshDefaults() -> UserDefaults {
        let name = "HealthTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func test_health_isOffUntilTurnedOn() {
        let settings = SettingsViewModel(workoutStore: FakeWorkoutStore(), defaults: freshDefaults())
        XCTAssertFalse(settings.healthEnabled)
        XCTAssertEqual(settings.healthKind, .recovery)
    }

    func test_turningOn_withPermission_isRemembered() async {
        let defaults = freshDefaults()
        let settings = SettingsViewModel(workoutStore: FakeWorkoutStore(), defaults: defaults)

        await settings.setHealthEnabled(true)
        settings.healthKind = .coreTraining

        XCTAssertTrue(settings.healthEnabled)
        XCTAssertNil(settings.healthMessage)
        XCTAssertEqual(HealthPreferences.load(from: defaults), HealthPreferences(isEnabled: true, kind: .coreTraining))
    }

    func test_turningOn_withoutPermission_staysOffAndExplains() async {
        let defaults = freshDefaults()
        let settings = SettingsViewModel(workoutStore: FakeWorkoutStore(grantsAccess: false), defaults: defaults)

        await settings.setHealthEnabled(true)

        XCTAssertFalse(settings.healthEnabled)
        XCTAssertNotNil(settings.healthMessage)
        XCTAssertFalse(HealthPreferences.load(from: defaults).isEnabled)
    }

    func test_turningOn_whereHealthIsUnavailable_staysOffAndExplains() async {
        let settings = SettingsViewModel(workoutStore: FakeWorkoutStore(isAvailable: false), defaults: freshDefaults())

        await settings.setHealthEnabled(true)

        XCTAssertFalse(settings.healthEnabled)
        XCTAssertNotNil(settings.healthMessage)
    }
}
