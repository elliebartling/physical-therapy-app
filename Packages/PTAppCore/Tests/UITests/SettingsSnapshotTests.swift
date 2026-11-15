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

    func test_settingsShowsIllustrationCredit() throws {
        let view = SettingsView(viewModel: SettingsViewModel(), onReplaceRoutine: {})
        XCTAssertNoThrow(try view.inspect().find(
            text: "Exercise illustrations by Bryl Lim, licensed CC BY-SA 4.0. Derived from Everkinetic."))
    }

    func test_settingsLinksToLicence() throws {
        let view = SettingsView(viewModel: SettingsViewModel(), onReplaceRoutine: {})
        let link = try view.inspect().find(ViewType.Link.self)
        XCTAssertEqual(try link.url().absoluteString, "https://creativecommons.org/licenses/by-sa/4.0/")
    }
}
