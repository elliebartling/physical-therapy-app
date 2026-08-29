import Foundation
import Observation

/// One step of a guided session: a work set (timed hold or counted reps) or a rest.
public struct PlayerStep: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case work
        case rest
    }

    public enum Goal: Hashable, Sendable {
        case timed(Int)
        case reps(Int)
    }

    public let id: UUID
    public let exercise: ExercisePayload
    public let kind: Kind
    public let goal: Goal
    public let setNumber: Int
    public let totalSets: Int
    public let side: String?

    public var title: String {
        kind == .rest ? "Rest" : exercise.name
    }

    public var subtitle: String {
        var parts = ["Set \(setNumber) of \(totalSets)"]
        if let side {
            parts.append("\(side) side")
        }
        return parts.joined(separator: " · ")
    }
}

public enum PlayerEvent: Sendable {
    case stepStarted
    case tick(remaining: Int)
    case countdownWarning
    case stepCompleted
    case finished
}

/// Drives a session step-by-step. Timed steps count down and auto-advance;
/// rep steps wait for the user to tap done. Shared by the iOS and watchOS players.
@MainActor
@Observable
public final class PlayerEngine {
    public private(set) var steps: [PlayerStep] = []
    public private(set) var currentIndex = 0
    public private(set) var remainingSeconds = 0
    public private(set) var isPaused = false
    public private(set) var isFinished = false
    public private(set) var startedAt = Date.now

    public var onEvent: (@MainActor (PlayerEvent) -> Void)?

    public let routine: RoutinePayload
    private var timerTask: Task<Void, Never>?
    private var completedWork: [UUID: (sets: Int, reps: Int, holdSeconds: Int)] = [:]

    public init(routine: RoutinePayload) {
        self.routine = routine
        self.steps = Self.buildSteps(for: routine)
    }

    public var currentStep: PlayerStep? {
        steps.indices.contains(currentIndex) ? steps[currentIndex] : nil
    }

    public var progress: Double {
        steps.isEmpty ? 0 : Double(currentIndex) / Double(steps.count)
    }

    public static func buildSteps(for routine: RoutinePayload) -> [PlayerStep] {
        var steps: [PlayerStep] = []
        for exercise in routine.exercises {
            let sides: [String?] = exercise.isPerSide ? ["Left", "Right"] : [nil]
            let totalSets = max(1, exercise.sets)
            for set in 1...totalSets {
                for (sideIndex, side) in sides.enumerated() {
                    let goal: PlayerStep.Goal = exercise.isTimed
                        ? .timed(exercise.holdSeconds ?? 30)
                        : .reps(exercise.reps ?? 10)
                    steps.append(PlayerStep(
                        id: UUID(),
                        exercise: exercise,
                        kind: .work,
                        goal: goal,
                        setNumber: set,
                        totalSets: totalSets,
                        side: side
                    ))
                    let isLastOfExercise = set == totalSets && sideIndex == sides.count - 1
                    if exercise.restSeconds > 0 && !isLastOfExercise {
                        steps.append(PlayerStep(
                            id: UUID(),
                            exercise: exercise,
                            kind: .rest,
                            goal: .timed(exercise.restSeconds),
                            setNumber: set,
                            totalSets: totalSets,
                            side: side
                        ))
                    }
                }
            }
        }
        return steps
    }

    public func start() {
        startedAt = .now
        enterStep(at: 0)
    }

    public func togglePause() {
        isPaused.toggle()
    }

    /// Finishes the current step. For rep steps this is the "done" tap;
    /// for timed steps it ends the countdown early but still counts the work.
    public func completeCurrentStep() {
        guard let step = currentStep, !isFinished else { return }
        timerTask?.cancel()
        if step.kind == .work {
            record(step)
        }
        onEvent?(.stepCompleted)
        enterStep(at: currentIndex + 1)
    }

    /// Advances without crediting the work.
    public func skipCurrentStep() {
        guard !isFinished else { return }
        timerTask?.cancel()
        enterStep(at: currentIndex + 1)
    }

    public func endEarly() {
        finish()
    }

    public func results(endedAt: Date = .now, source: String) -> CompletedSessionPayload {
        CompletedSessionPayload(
            id: UUID(),
            routineID: routine.id,
            routineName: routine.name,
            startedAt: startedAt,
            endedAt: endedAt,
            source: source,
            exercises: routine.exercises.map { exercise in
                let work = completedWork[exercise.id] ?? (sets: 0, reps: 0, holdSeconds: 0)
                return CompletedExercisePayload(
                    exerciseID: exercise.id,
                    name: exercise.name,
                    targetSets: max(1, exercise.sets) * (exercise.isPerSide ? 2 : 1),
                    completedSets: work.sets,
                    totalReps: work.reps,
                    totalHoldSeconds: work.holdSeconds,
                    skipped: work.sets == 0
                )
            }
        )
    }

    // MARK: - Private

    private func enterStep(at index: Int) {
        timerTask?.cancel()
        guard steps.indices.contains(index) else {
            finish()
            return
        }
        currentIndex = index
        isPaused = false
        let step = steps[index]
        onEvent?(.stepStarted)
        switch step.goal {
        case .timed(let seconds):
            remainingSeconds = seconds
            runTimer()
        case .reps:
            remainingSeconds = 0
        }
    }

    private func runTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                guard !self.isPaused else { continue }
                self.remainingSeconds -= 1
                self.onEvent?(.tick(remaining: self.remainingSeconds))
                if self.remainingSeconds == 3 {
                    self.onEvent?(.countdownWarning)
                }
                if self.remainingSeconds <= 0 {
                    self.completeCurrentStep()
                    return
                }
            }
        }
    }

    private func record(_ step: PlayerStep) {
        var entry = completedWork[step.exercise.id] ?? (sets: 0, reps: 0, holdSeconds: 0)
        entry.sets += 1
        switch step.goal {
        case .reps(let count):
            entry.reps += count
        case .timed(let seconds):
            entry.holdSeconds += seconds
        }
        completedWork[step.exercise.id] = entry
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        timerTask?.cancel()
        onEvent?(.finished)
    }
}
