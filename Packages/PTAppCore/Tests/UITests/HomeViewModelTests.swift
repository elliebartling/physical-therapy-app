import XCTest
import DataKit
import HistoryKit
@testable import UI

@MainActor
final class HomeViewModelTests: XCTestCase {
    func test_loadsStreakAndWeekFromRepository() async throws {
        let container = try ModelContainerFactory.inMemory()
        let ctx = container.mainContext
        let routineRepo = RoutineRepository(context: ctx)
        let sessionRepo = SessionRepository(context: ctx)

        try routineRepo.save(Routine(name: "T"))
        let today = Calendar.current.startOfDay(for: .now)
        let s = SessionRecord(routineID: UUID(), startedAt: today, completedAt: today)
        try sessionRepo.insert(s)

        let vm = HomeViewModel(routineRepo: routineRepo, sessionRepo: sessionRepo, today: today)
        await vm.refresh()

        XCTAssertTrue(vm.hasRoutine)
        XCTAssertEqual(vm.streak, 1)
        XCTAssertTrue(vm.isDoneToday)
        XCTAssertEqual(vm.headline, "Done for today.")

        // Hold container alive for the duration of the test (DataKit milestone showed
        // ModelContext keeps only a weak ref to its container).
        _ = container
    }

    func test_buildsNumberedRowsAndEstimateFromActiveRoutine() async throws {
        let container = try ModelContainerFactory.inMemory()
        let ctx = container.mainContext
        let routineRepo = RoutineRepository(context: ctx)
        let sessionRepo = SessionRepository(context: ctx)

        try routineRepo.save(Routine(name: "Knee Rehab", exercises: [
            Exercise(name: "Side plank", target: .timeSets(seconds: 30, sets: 3), restSeconds: 30, side: .alternating, order: 1),
            Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 2), restSeconds: 0, side: .both, order: 0),
        ]))

        let vm = HomeViewModel(routineRepo: routineRepo, sessionRepo: sessionRepo)
        await vm.refresh()

        XCTAssertEqual(vm.routineName, "Knee Rehab")
        XCTAssertEqual(vm.rows.map(\.number), ["01", "02"])
        XCTAssertEqual(vm.rows.map(\.name), ["Bridges", "Side plank"])
        XCTAssertEqual(vm.rows.map(\.prescription), ["2×10", "3×30s L/R"])
        XCTAssertEqual(vm.estimatedMinutes, 4) // 60s + 150s = 210s → 4 min
        XCTAssertEqual(vm.headline, "Ready when you are.")

        _ = container
    }

    func test_rowsCarryArtChoice() async throws {
        let container = try ModelContainerFactory.inMemory()
        let ctx = container.mainContext
        let routineRepo = RoutineRepository(context: ctx)
        let sessionRepo = SessionRepository(context: ctx)
        try routineRepo.save(Routine(name: "R", exercises: [
            Exercise(name: "Bird Dog", target: .repsSets(reps: 10, sets: 3), restSeconds: 30,
                     side: .both, order: 0, art: .library(slug: "bird-dog")),
            Exercise(name: "Stretch", target: .repsSets(reps: 5, sets: 1), restSeconds: 0,
                     side: .both, order: 1, art: ArtChoice.none),
        ]))
        let vm = HomeViewModel(routineRepo: routineRepo, sessionRepo: sessionRepo)
        await vm.refresh()
        XCTAssertEqual(vm.rows.map(\.art), [.library(slug: "bird-dog"), ArtChoice.none])
        _ = container
    }
}
