import XCTest
import SwiftUI
import ViewInspector
@testable import UI

@MainActor
final class SettingsSnapshotTests: XCTestCase {
    func test_remindersSectionVisible() throws {
        let vm = SettingsViewModel()
        let view = SettingsView(viewModel: vm, onReplaceRoutine: {})
        XCTAssertNoThrow(try view.inspect().find(text: "Reminder"))
    }
}
