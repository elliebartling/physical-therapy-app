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

    private var isPaused = false
    private var pauseContinuation: CheckedContinuation<Void, Never>?

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
        continuation.yield(.paused)
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        pauseContinuation?.resume(); pauseContinuation = nil
        continuation.yield(.resumed)
    }

    public func skipCurrentSet() async throws {
        setCompletion?.resume()
        setCompletion = nil
    }

    private func awaitIfPaused() async {
        guard isPaused else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            pauseContinuation = cont
        }
    }

    private func runExercise(_ exercise: Exercise) async throws {
        let totalSets = exercise.target.totalSets
        for setIndex in 0..<totalSets {
            await Task.yield()
            await awaitIfPaused()
            currentSetIndex = setIndex

            let effectiveSide: Side
            if exercise.side == .alternating {
                effectiveSide = setIndex.isMultiple(of: 2) ? .left : .right
            } else {
                effectiveSide = exercise.side
            }
            continuation.yield(.setStarted(setIndex: setIndex, totalSets: totalSets, side: effectiveSide))
            if setIndex > 0, exercise.side == .alternating {
                continuation.yield(.sideSwitch(to: effectiveSide))
            }

            switch exercise.target {
            case .repsSets:
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    setCompletion = cont
                }
            case .timeSets(let seconds, _):
                try await clock.sleep(seconds: Double(seconds))
            }

            await Task.yield()
            await awaitIfPaused()

            let isLastSet = setIndex == totalSets - 1
            if !isLastSet, exercise.restSeconds > 0 {
                continuation.yield(.rest(seconds: exercise.restSeconds))
                try await clock.sleep(seconds: Double(exercise.restSeconds))
            }
        }
    }
}
