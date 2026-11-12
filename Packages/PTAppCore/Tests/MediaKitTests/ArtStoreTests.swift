import XCTest
@testable import MediaKit

final class ArtStoreTests: XCTestCase {
    func test_downloadsOnceThenServesFromCache() async {
        let dl = StubFrameDownloader()
        let store = ArtStore(downloader: dl, directory: tempDir())
        let a = await store.frame(slug: "bird-dog", frame: 1)
        let b = await store.frame(slug: "bird-dog", frame: 1)
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
        let calls = await dl.callCount
        XCTAssertEqual(calls, 1)
    }

    func test_cacheSurvivesANewStoreOverTheSameDirectory() async {
        let dir = tempDir()
        let dl = StubFrameDownloader()
        _ = await ArtStore(downloader: dl, directory: dir).frame(slug: "clamshell", frame: 1)
        _ = await ArtStore(downloader: dl, directory: dir).frame(slug: "clamshell", frame: 1)
        let calls = await dl.callCount
        XCTAssertEqual(calls, 1)
    }

    func test_offlineReturnsNilAndRetriesLater() async {
        // First launch with no network.
        let dir = tempDir()
        let offline = await ArtStore(downloader: StubFrameDownloader(failing: true), directory: dir)
            .frame(slug: "bird-dog", frame: 1)
        XCTAssertNil(offline)
        // A later launch with network succeeds: the failure was not cached.
        let online = await ArtStore(downloader: StubFrameDownloader(), directory: dir)
            .frame(slug: "bird-dog", frame: 1)
        XCTAssertNotNil(online)
    }

    func test_failedFetchLeavesNoStuckTaskInTheSameStore() async {
        let failing = StubFrameDownloader(failing: true)
        let store = ArtStore(downloader: failing, directory: tempDir())
        let first = await store.frame(slug: "bird-dog", frame: 1)
        let second = await store.frame(slug: "bird-dog", frame: 1)
        XCTAssertNil(first)
        XCTAssertNil(second)
        let calls = await failing.callCount
        XCTAssertEqual(calls, 2, "a failed fetch must not be remembered")
    }

    func test_unknownSlugReturnsNilWithoutDownloading() async {
        let dl = StubFrameDownloader()
        let store = ArtStore(downloader: dl, directory: tempDir())
        let result = await store.frame(slug: "bench-press", frame: 1)
        XCTAssertNil(result)
        let calls = await dl.callCount
        XCTAssertEqual(calls, 0)
    }

    func test_concurrentRequestsForTheSameFrameDownloadOnce() async {
        let dl = StubFrameDownloader()
        let store = ArtStore(downloader: dl, directory: tempDir())
        await withTaskGroup(of: Void.self) { g in
            for _ in 0..<8 { g.addTask { _ = await store.frame(slug: "dead-bug", frame: 1) } }
        }
        let calls = await dl.callCount
        XCTAssertEqual(calls, 1)
    }

    func test_createsMissingCacheDirectory() async {
        let dir = tempDir().appendingPathComponent("nested/art", isDirectory: true)
        let store = ArtStore(downloader: StubFrameDownloader(), directory: dir)
        let result = await store.frame(slug: "bird-dog", frame: 2)
        XCTAssertNotNil(result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func test_prefetchFetchesEveryFrameOfEachSlug() async {
        let dl = StubFrameDownloader()
        let store = ArtStore(downloader: dl, directory: tempDir())
        await store.prefetch(slugs: ["bird-dog", "clamshell"])
        let calls = await dl.callCount
        XCTAssertEqual(calls, 6)
    }

    func test_cdnURLShape() {
        let url = CDNFrameDownloader.url(slug: "bird-dog", frame: 1)
        XCTAssertEqual(
            url?.absoluteString,
            "https://cdn.jsdelivr.net/npm/@bryllim/workout-guide@1.0.0/assets/bird-dog/frame-1.png"
        )
    }
}
