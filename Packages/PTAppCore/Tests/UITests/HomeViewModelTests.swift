import XCTest
import DataKit
import HistoryKit
@testable import UI

@MainActor
final class HomeViewModelTests: XCTestCase {
    func test_loadsStreakAndHeatmapFromRepository() async throws {
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
        XCTAssertTrue(vm.heatmap.completedDayNumbers.contains(Calendar.current.component(.day, from: today)))

        // Hold container alive for the duration of the test (DataKit milestone showed
        // ModelContext keeps only a weak ref to its container).
        _ = container
    }
}
