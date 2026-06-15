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
}
