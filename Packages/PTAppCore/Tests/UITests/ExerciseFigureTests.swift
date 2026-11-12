import XCTest
import SwiftUI
import ViewInspector
import DataKit
import MediaKit
@testable import UI

@MainActor
final class ExerciseFigureTests: XCTestCase {
    func test_noPictureStatesRenderNothingVisible() throws {
        let store = ArtStore(downloader: StubFrameDownloader(failing: true), directory: tempDir())
        for art in [ArtChoice.unmatched, .none, .library(slug: "bench-press")] {
            let v = ExerciseFigure(art: art, store: store)
            XCTAssertThrowsError(try v.inspect().find(ViewType.Image.self), "\(art)")
        }
    }

    func test_figureIsHiddenFromVoiceOver() throws {
        let v = ExerciseFigure(art: .library(slug: "bird-dog"),
                               store: ArtStore(downloader: StubFrameDownloader(), directory: tempDir()))
        XCTAssertTrue(try v.inspect().find(ViewType.Color.self).accessibilityHidden())
    }

    func test_hiddenFromVoiceOverEvenWithNoPicture() throws {
        let store = ArtStore(downloader: StubFrameDownloader(failing: true), directory: tempDir())
        for art in [ArtChoice.unmatched, .none] {
            XCTAssertTrue(try ExerciseFigure(art: art, store: store).inspect().find(ViewType.Color.self).accessibilityHidden(), "\(art)")
        }
    }

    func test_environmentProvidesADefaultStore() {
        // Reading the default must not crash or require setup.
        _ = EnvironmentValues().artStore
    }
}
