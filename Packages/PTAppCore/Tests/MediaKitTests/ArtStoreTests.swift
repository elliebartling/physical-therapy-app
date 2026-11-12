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

    func test_concurrentRequestsForTheSameFrameDownloadOnce() async throws {
        // The first download is held open, so the other callers must arrive
        // while it is in flight. Without dedup each would start its own.
        let dl = StubFrameDownloader(holdFirstCall: true)
        let store = ArtStore(downloader: dl, directory: tempDir())
        // A slug that left the catalogue would fail every call and the wait below would spin forever.
        _ = try XCTUnwrap(ExerciseCatalog.bundled.entry(slug: "dead-bug"))
        let results = await withTaskGroup(of: Data?.self) { g -> [Data?] in
            for _ in 0..<8 { g.addTask { await store.frame(slug: "dead-bug", frame: 1) } }
            while await dl.callCount == 0 { await Task.yield() }
            try? await Task.sleep(for: .milliseconds(100))
            let heldCalls = await dl.callCount
            XCTAssertEqual(heldCalls, 1, "callers must wait on the in-flight download")
            await dl.release()
            var all: [Data?] = []
            for await r in g { all.append(r) }
            return all
        }
        XCTAssertEqual(results.count, 8)
        XCTAssertTrue(results.allSatisfy { $0 != nil })
        let calls = await dl.callCount
        XCTAssertEqual(calls, 1)
    }

    func test_framesOutsideTheRangeReturnNilWithoutDownloading() async {
        let dl = StubFrameDownloader()
        let store = ArtStore(downloader: dl, directory: tempDir())
        let low = await store.frame(slug: "bird-dog", frame: 0)
        let high = await store.frame(slug: "bird-dog", frame: 4)
        XCTAssertNil(low)
        XCTAssertNil(high)
        let calls = await dl.callCount
        XCTAssertEqual(calls, 0)
    }

    func test_nonPNGBodyIsNotCachedAndRetriesLater() async {
        let dir = tempDir()
        let html = Data("<html>captive portal</html>".utf8)
        let bad = await ArtStore(downloader: StubFrameDownloader(data: html), directory: dir)
            .frame(slug: "bird-dog", frame: 1)
        XCTAssertNil(bad)
        let good = await ArtStore(downloader: StubFrameDownloader(), directory: dir)
            .frame(slug: "bird-dog", frame: 1)
        XCTAssertNotNil(good)
    }

    func test_cacheDirectoryIsExcludedFromBackup() async throws {
        let dir = tempDir().appendingPathComponent("art", isDirectory: true)
        _ = await ArtStore(downloader: StubFrameDownloader(), directory: dir)
            .frame(slug: "bird-dog", frame: 1)
        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func test_pngSignatureCheck() {
        XCTAssertTrue(PNGSignature.matches(Data(PNGSignature.bytes + [0x00])))
        XCTAssertFalse(PNGSignature.matches(Data([0x89, 0x50, 0x4E, 0x47])))
        XCTAssertFalse(PNGSignature.matches(Data("<html>".utf8)))
    }

    func test_createsMissingCacheDirectory() async {
        let dir = tempDir().appendingPathComponent("nested/art", isDirectory: true)
        let store = ArtStore(downloader: StubFrameDownloader(), directory: dir)
        let result = await store.frame(slug: "bird-dog", frame: 2)
        XCTAssertNotNil(result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func test_cdnURLShape() {
        let url = CDNFrameDownloader.url(slug: "bird-dog", frame: 1)
        XCTAssertEqual(
            url?.absoluteString,
            "https://cdn.jsdelivr.net/npm/@bryllim/workout-guide@1.0.0/assets/bird-dog/frame-1.png"
        )
    }
}
