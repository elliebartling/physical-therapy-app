import XCTest
import SwiftUI
import ViewInspector
import DataKit
@testable import UI

@MainActor
final class HomeSnapshotTests: XCTestCase {
    func test_emptyState_showsSetupCTA() throws {
        let c = try ModelContainerFactory.inMemory()
        let vm = HomeViewModel(
            routineRepo: RoutineRepository(context: c.mainContext),
            sessionRepo: SessionRepository(context: c.mainContext)
        )
        let view = HomeView(viewModel: vm, onStart: {}, onSettings: {}, onSetup: {})
        XCTAssertNoThrow(try view.inspect().find(text: "No routine yet"))
        _ = c
    }

    func test_routineMenu_offersANewSheetFromPT_whichOpensSetup() async throws {
        let c = try ModelContainerFactory.inMemory()
        let routineRepo = RoutineRepository(context: c.mainContext)
        try routineRepo.save(Routine(name: "Knee", exercises: [
            Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both, order: 0)
        ]))
        let vm = HomeViewModel(routineRepo: routineRepo, sessionRepo: SessionRepository(context: c.mainContext))
        await vm.refresh()
        var openedSetup = false
        let view = HomeView(viewModel: vm, onStart: {}, onSettings: {}, onSetup: { openedSetup = true })

        try view.inspect().find(button: "New sheet from PT…").tap()

        XCTAssertTrue(openedSetup)
        _ = c
    }
}
