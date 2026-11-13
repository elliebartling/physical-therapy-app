import Foundation
import DataKit

@MainActor
public final class SessionEngine {
    private let routine: Routine
    private let clock: Clock
    private var exercises: [Exercise] { routine.exercises.sorted { $0.order < $1.order } }

    public let events: AsyncStream<PhaseEvent>
    private let continuation: AsyncStream<PhaseEvent>.Continuation

    private var currentExerciseIndex = 0
    private var currentSetIndex = 0
    private var setCompletion: CheckedContinuation<Void, Never>?
    /// Signals the hold or rest currently being timed to end early.
    private var skipCurrentWait: AsyncStream<Void>.Continuation?

    private var isPaused = false
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    /// Interrupts the hold or rest currently being timed so it stops counting while paused.
    private var pauseCurrentWait: AsyncStream<Void>.Continuation?
    /// A skip pressed while a timed hold or rest is paused; it ends that wait on resume.
    private var skipWhilePaused = false
    private var isTiming = false

    public init(routine: Routine, clock: Clock = SystemClock()) {
        self.routine = routine
        self.clock = clock
        var cont: AsyncStream<PhaseEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    public func start() async throws {
        continuation.yield(.sessionStarted)
        for (idx, exercise) in exercises.enumerated() {
            currentExerciseIndex = idx
            continuation.yield(.exerciseStarted(
                exerciseID: exercise.id, index: idx, totalExercises: exercises.count
            ))
            try await runExercise(exercise)
            continuation.yield(.exerciseCompleted(exerciseID: exercise.id))
        }
        continuation.yield(.sessionCompleted)
        continuation.finish()
    }

    public func completeCurrentSet() async throws {
        setCompletion?.resume()
        setCompletion = nil
    }

    public func pause() {
        guard !isPaused else { return }
        isPaused = true
        pauseCurrentWait?.yield()
        continuation.yield(.paused)
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        pauseContinuation?.resume(); pauseContinuation = nil
        continuation.yield(.resumed)
    }

    /// Moves to the next step: ends a reps set, a timed hold, or a rest early.
    public func skipCurrentSet() async throws {
        setCompletion?.resume()
        setCompletion = nil
        if isTiming, isPaused { skipWhilePaused = true }
        skipCurrentWait?.yield()
    }

    private enum WaitOutcome: Sendable { case elapsed, skipped, paused }

    /// Times a hold or rest on the clock. Pausing stops the count and resuming carries on
    /// with what was left; `skipCurrentSet()` ends it early. Still throws if the session's
    /// own task is cancelled.
    private func timedWait(seconds: Double) async throws {
        isTiming = true
        defer { isTiming = false; skipWhilePaused = false }
        var remaining = seconds
        while remaining > 0 {
            await awaitIfPaused()
            if skipWhilePaused { return }
            let started = clock.now
            switch try await sleepUntilInterrupted(seconds: remaining) {
            case .elapsed, .skipped: return
            case .paused: remaining -= clock.now.timeIntervalSince(started)
            }
        }
    }

    /// One uninterrupted stretch of a timed wait: ends when the time is up, on a skip or on a pause.
    private func sleepUntilInterrupted(seconds: Double) async throws -> WaitOutcome {
        let (skips, skipSignal) = AsyncStream<Void>.makeStream()
        let (pauses, pauseSignal) = AsyncStream<Void>.makeStream()
        skipCurrentWait = skipSignal
        pauseCurrentWait = pauseSignal
        defer {
            skipCurrentWait = nil
            pauseCurrentWait = nil
            skipSignal.finish()
            pauseSignal.finish()
        }
        let clock = self.clock
        let outcome = try await withThrowingTaskGroup(of: WaitOutcome.self) { group in
            group.addTask { try await clock.sleep(seconds: seconds); return .elapsed }
            group.addTask { for await _ in skips { return .skipped }; return .skipped }
            group.addTask { for await _ in pauses { return .paused }; return .paused }
            let first = try await group.next() ?? .elapsed
            group.cancelAll()
            return first
        }
        try Task.checkCancellation()
        return outcome
    }

    private func awaitIfPaused() async {
        guard isPaused else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            pauseContinuation = cont
        }
    }

    /// An alternating exercise does each set on the left and then the right, so "3 sets"
    /// means three per side; rest comes between full sets.
    private func runExercise(_ exercise: Exercise) async throws {
        let totalSets = exercise.target.totalSets
        let sides: [Side] = exercise.side == .alternating ? [.left, .right] : [exercise.side]
        for setIndex in 0..<totalSets {
            currentSetIndex = setIndex
            for (sideIndex, side) in sides.enumerated() {
                await Task.yield()
                await awaitIfPaused()
                continuation.yield(.setStarted(setIndex: setIndex, totalSets: totalSets, side: side))
                if sideIndex > 0 {
                    continuation.yield(.sideSwitch(to: side))
                }

                switch exercise.target {
                case .repsSets:
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        setCompletion = cont
                    }
                case .timeSets(let seconds, _):
                    try await timedWait(seconds: Double(seconds))
                }
            }

            await Task.yield()
            await awaitIfPaused()

            let isLastSet = setIndex == totalSets - 1
            if !isLastSet, exercise.restSeconds > 0 {
                continuation.yield(.rest(seconds: exercise.restSeconds))
                try await timedWait(seconds: Double(exercise.restSeconds))
            }
        }
    }
}
