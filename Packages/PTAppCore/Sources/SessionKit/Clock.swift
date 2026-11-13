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

/// A clock whose sleeps only end when the test moves time on with `advance(by:)`,
/// for checking what happens part-way through a hold or rest.
public final class ManualClock: Clock, @unchecked Sendable {
    private struct Sleeper {
        let id: UUID
        let deadline: Date
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var current: Date
    private var sleepers: [Sleeper] = []

    public init(start: Date = Date(timeIntervalSince1970: 0)) { self.current = start }

    public var now: Date { lock.withLock { current } }

    public func sleep(seconds: Double) async throws {
        let id = UUID()
        let deadline = now.addingTimeInterval(seconds)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock {
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if current >= deadline {
                        continuation.resume()
                    } else {
                        sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    }
                }
            }
        } onCancel: {
            let cancelled = lock.withLock { () -> Sleeper? in
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    public func advance(by seconds: Double) {
        let woken = lock.withLock { () -> [Sleeper] in
            current.addTimeInterval(seconds)
            let due = sleepers.filter { $0.deadline <= current }
            sleepers.removeAll { $0.deadline <= current }
            return due
        }
        woken.forEach { $0.continuation.resume() }
    }
}
