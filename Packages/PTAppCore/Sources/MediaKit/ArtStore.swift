import Foundation
import os

private let logger = Logger(subsystem: "PTAppCore", category: "media")

/// Resolves exercise illustration frames: disk cache first, then the
/// network. A missing picture is a normal state, so `frame` never throws.
public actor ArtStore {
    /// Frames per exercise are numbered 1...3.
    static let frameRange = 1...3

    private let downloader: FrameDownloading
    private let directory: URL
    private let catalog: ExerciseCatalog
    private var inFlight: [String: Task<Data?, Never>] = [:]

    public init(downloader: FrameDownloading = CDNFrameDownloader(), directory: URL? = nil) {
        self.downloader = downloader
        self.directory = directory ?? Self.defaultDirectory()
        self.catalog = .bundled
    }

    /// The frame's PNG data, or nil when there is no picture to show:
    /// unknown exercise, not downloaded yet, or offline.
    public func frame(slug: String, frame: Int) async -> Data? {
        // Slugs outside the bundled catalogue (e.g. a stored choice from an
        // older app version) never reach the network.
        guard catalog.entry(slug: slug) != nil, Self.frameRange.contains(frame) else {
            return nil
        }
        let key = "\(slug)/\(frame)"
        let file = directory.appendingPathComponent("\(slug)-\(frame).png")

        if let cached = try? Data(contentsOf: file), !cached.isEmpty {
            return cached
        }
        // Concurrent callers await the one download already under way.
        if let running = inFlight[key] {
            return await running.value
        }
        let task = Task { [self] in
            let result = await fetchAndStore(slug: slug, frame: frame, file: file)
            // Success or failure, forget the task so a later call can retry.
            // Runs before the task completes, so no caller can see a stale one.
            finish(key)
            return result
        }
        inFlight[key] = task
        return await task.value
    }

    /// Warms the cache for these exercises. Failures are fine; they retry
    /// the next time a frame is asked for.
    public func prefetch(slugs: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for slug in slugs {
                for n in Self.frameRange {
                    group.addTask { [self] in _ = await frame(slug: slug, frame: n) }
                }
            }
        }
    }

    private func finish(_ key: String) {
        inFlight[key] = nil
    }

    private func fetchAndStore(slug: String, frame: Int, file: URL) async -> Data? {
        let data: Data
        do {
            data = try await downloader.data(slug: slug, frame: frame)
        } catch {
            // Offline is routine and nothing is written, so the next
            // attempt starts clean.
            logger.info("No art for \(slug, privacy: .public) frame \(frame): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Atomic, so a second store over this directory never reads a partial file.
            try data.write(to: file, options: .atomic)
        } catch {
            logger.error("Could not cache \(slug, privacy: .public) frame \(frame): \(error.localizedDescription, privacy: .public)")
        }
        return data
    }

    private static func defaultDirectory() -> URL {
        let base: URL
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            base = support
        } else {
            logger.error("Application Support unavailable; caching art in the temporary directory")
            base = FileManager.default.temporaryDirectory
        }
        return base.appendingPathComponent("ExerciseArt", isDirectory: true)
    }
}
