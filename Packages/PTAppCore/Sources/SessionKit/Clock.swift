import Foundation

public protocol Clock: Sendable {
    var now: Date { get }
    func sleep(seconds: Double) async throws
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { .now }
    public func sleep(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

public final class TestClock: Clock, @unchecked Sendable {
    public private(set) var now: Date
    public init(start: Date = Date(timeIntervalSince1970: 0)) { self.now = start }
    public func advance(by seconds: Double) { now.addTimeInterval(seconds) }
    public func sleep(seconds: Double) async throws { advance(by: seconds) }
}
