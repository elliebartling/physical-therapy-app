import XCTest
import SwiftUI
import ViewInspector
import DataKit
@testable import UI

@MainActor
final class SetupViewTests: XCTestCase {
    func test_editor_hasACancel_thatGoesBackToChoosingASource() throws {
        let container = try ModelContainerFactory.inMemory()
        let vm = SetupViewModel(routineRepo: RoutineRepository(context: container.mainContext))
        vm.startManual()
        let view = SetupView(viewModel: vm, onDone: {})

        try view.inspect().find(button: "Cancel").tap()

        XCTAssertEqual(vm.phase, .idle)
        XCTAssertNil(vm.editorVM)
        _ = container
    }
}
