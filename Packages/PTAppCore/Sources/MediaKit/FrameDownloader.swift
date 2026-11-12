import Foundation

/// Fetches the bytes of one illustration frame. Throws on any failure;
/// `ArtStore` is what turns failure into "no picture".
public protocol FrameDownloading: Sendable {
    func data(slug: String, frame: Int) async throws -> Data
}

public enum FrameDownloadError: Error, Sendable, Equatable {
    case badURL
    case badStatus(Int)
    case emptyBody
    case stubFailure
}

/// Downloads frames from the package CDN.
public struct CDNFrameDownloader: FrameDownloading {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    static let base = "https://cdn.jsdelivr.net/npm/@bryllim/workout-guide@1.0.0/assets"

    static func url(slug: String, frame: Int) -> URL? {
        URL(string: "\(base)/\(slug)/frame-\(frame).png")
    }

    public func data(slug: String, frame: Int) async throws -> Data {
        guard let url = Self.url(slug: slug, frame: frame) else {
            throw FrameDownloadError.badURL
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FrameDownloadError.badStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw FrameDownloadError.emptyBody }
        return data
    }
}

/// A downloader for tests and previews: no network, counts its calls.
public actor StubFrameDownloader: FrameDownloading {
    private let payload: Data
    private let failing: Bool
    public private(set) var callCount = 0

    public init(data: Data = Data([0x89, 0x50, 0x4E, 0x47]), failing: Bool = false) {
        self.payload = data
        self.failing = failing
    }

    public func data(slug: String, frame: Int) async throws -> Data {
        callCount += 1
        // Suspend once so concurrent callers genuinely overlap.
        await Task.yield()
        if failing { throw FrameDownloadError.stubFailure }
        return payload
    }
}
