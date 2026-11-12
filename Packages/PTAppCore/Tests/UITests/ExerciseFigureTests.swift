import XCTest
import SwiftUI
import ViewInspector
import DataKit
import MediaKit
@testable import UI

@MainActor
final class ExerciseFigureTests: XCTestCase {
    /// A real, decodable 1x1 PNG.
    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==") ?? Data()

    private func pixel() throws -> UIImage {
        try XCTUnwrap(UIImage(data: Self.onePixelPNG), "fixture PNG must decode")
    }

    // MARK: canvas

    func test_canvasWithAnImage_rendersATemplateImage() throws {
        let sut = ExerciseFigureCanvas(image: try pixel())
        let image = try sut.inspect().find(ViewType.Image.self)
        XCTAssertEqual(try image.actualImage().uiImage().renderingMode, .alwaysTemplate)
    }

    func test_canvasWithAnImage_isHiddenFromVoiceOver() throws {
        let sut = ExerciseFigureCanvas(image: try pixel())
        XCTAssertTrue(try sut.inspect().find(ViewType.Image.self).accessibilityHidden())
    }

    func test_canvasWithoutAnImage_rendersNoImageAndIsHidden() throws {
        let sut = ExerciseFigureCanvas(image: nil)
        XCTAssertThrowsError(try sut.inspect().find(ViewType.Image.self))
        XCTAssertTrue(try sut.inspect().find(ViewType.Color.self).accessibilityHidden())
    }

    // MARK: first render

    func test_firstRender_showsNoImageForEveryArtChoice() throws {
        let store = ArtStore(downloader: StubFrameDownloader(), directory: tempDir())
        for art in [ArtChoice.unmatched, .none, .library(slug: "bench-press")] {
            let sut = ExerciseFigure(art: art, store: store)
            XCTAssertThrowsError(try sut.inspect().find(ViewType.Image.self), "\(art)")
        }
    }

    // MARK: loading

    func test_loadImage_decodesAFrameFromTheStore() async throws {
        let store = ArtStore(downloader: StubFrameDownloader(data: Self.onePixelPNG), directory: tempDir())
        let image = await ExerciseFigure.loadImage(slug: "bird-dog", frame: 1, store: store)
        XCTAssertNotNil(image)
    }

    func test_loadImage_isNilWhenOfflineOrUnmatched() async {
        let store = ArtStore(downloader: StubFrameDownloader(failing: true), directory: tempDir())
        let offline = await ExerciseFigure.loadImage(slug: "bench-press", frame: 1, store: store)
        let unmatched = await ExerciseFigure.loadImage(slug: nil, frame: 1, store: store)
        XCTAssertNil(offline)
        XCTAssertNil(unmatched)
    }

    // MARK: environment

    func test_storeFallsBackToTheEnvironmentWhenNoneIsPassed() {
        let env = ArtStore(downloader: StubFrameDownloader(), directory: tempDir())
        let explicit = ArtStore(downloader: StubFrameDownloader(), directory: tempDir())
        XCTAssertTrue(ExerciseFigure.resolveStore(explicit: nil, environment: env) === env)
        XCTAssertTrue(ExerciseFigure.resolveStore(explicit: explicit, environment: env) === explicit)
    }

    // MARK: onLoad (hosted, so the real task runs)

    private func reportedLoad(downloader: StubFrameDownloader) async -> Bool? {
        let store = ArtStore(downloader: downloader, directory: tempDir())
        let reported = expectation(description: "onLoad")
        var result: Bool?
        let sut = ExerciseFigure(art: .library(slug: "bird-dog"), store: store) { loaded in
            result = loaded
            reported.fulfill()
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.rootViewController = UIHostingController(rootView: sut.frame(width: 200, height: 200))
        window.makeKeyAndVisible()
        await fulfillment(of: [reported], timeout: 5)
        window.isHidden = true
        return result
    }

    func test_onLoad_reportsTrueWhenTheFrameArrives() async {
        let loaded = await reportedLoad(downloader: StubFrameDownloader(data: Self.onePixelPNG))
        XCTAssertEqual(loaded, true)
    }

    func test_onLoad_reportsFalseWhenNoFrameIsAvailable() async {
        let loaded = await reportedLoad(downloader: StubFrameDownloader(failing: true))
        XCTAssertEqual(loaded, false)
    }
}
