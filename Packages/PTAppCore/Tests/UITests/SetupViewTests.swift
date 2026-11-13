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

        // ViewInspector can't reach toolbar items, so take the editor setup shows and use its Cancel.
        let editor = try view.inspect().find(RoutineEditorView.self).actualView()
        let cancel = try XCTUnwrap(editor.onCancel, "setup's editor should offer Cancel")
        cancel()

        XCTAssertEqual(vm.phase, .idle)
        XCTAssertNil(vm.editorVM)
        _ = container
    }
}
