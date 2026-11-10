import Foundation
import Observation
import DataKit
import SessionKit

@MainActor
@Observable
public final class SessionViewModel {
    private let engine: SessionEngine
    private let routine: Routine
    private let sessionRepo: SessionRepository
    private let audio: AudioCueService?
    private let haptics: HapticService?

    public private(set) var currentExerciseName = ""
    public private(set) var currentSet: Int = 0
    public private(set) var totalSets: Int = 0
    public private(set) var currentSide: Side = .both
    public private(set) var isPaused = false
    public private(set) var isComplete = false
    public private(set) var resumeWindowExpired = false

    private var sessionRecord: SessionRecord
    private var exerciseStartedAt: Date = .now
    private var backgroundedAt: Date?

    public init(routine: Routine, sessionRepo: SessionRepository,
                clock: Clock = SystemClock(), audio: AudioCueService? = AudioCueService(),
                haptics: HapticService? = HapticService()) {
        self.routine = routine
        self.engine = SessionEngine(routine: routine, clock: clock)
        self.sessionRepo = sessionRepo
        self.audio = audio
        self.haptics = haptics
        self.sessionRecord = SessionRecord(routineID: routine.id, startedAt: .now)
    }

    public func run() async {
        let listener = Task { @MainActor in
            for await event in engine.events { self.handle(event) }
        }
        try? await engine.start()
        listener.cancel()
        sessionRecord.completedAt = .now
        try? sessionRepo.insert(sessionRecord)
        isComplete = true
    }

    public func pause() { engine.pause() }
    public func resume() { engine.resume() }
    public func completeCurrentSet() async { try? await engine.completeCurrentSet() }
    public func skipCurrentSet() async { try? await engine.skipCurrentSet() }

    public func appWillResignActive() {
        backgroundedAt = .now
        engine.pause()
    }

    public func appDidBecomeActive() {
        guard let bg = backgroundedAt else { return }
        backgroundedAt = nil
        if Date.now.timeIntervalSince(bg) > 600 { // 10 minutes
            resumeWindowExpired = true
            // Finalize as partial — completedAt stays nil.
            try? sessionRepo.insert(sessionRecord)
            isComplete = true
        }
    }

    private func handle(_ event: PhaseEvent) {
        switch event {
        case .sessionStarted: break
        case .exerciseStarted(let id, _, _):
            currentExerciseName = routine.exercises.first { $0.id == id }?.name ?? ""
            totalSets = routine.exercises.first { $0.id == id }?.target.totalSets ?? 0
            exerciseStartedAt = .now
        case .setStarted(let i, let total, let side):
            currentSet = i + 1
            totalSets = total
            currentSide = side
            audio?.play(.setStart)
            haptics?.fire(.mediumTick)
        case .rest:
            audio?.play(.rest)
            haptics?.fire(.lightTick)
        case .sideSwitch(let side):
            currentSide = side
            haptics?.fire(.lightTick)
        case .exerciseCompleted(let id):
            audio?.play(.exerciseDone)
            haptics?.fire(.success)
            sessionRecord.exerciseRecords.append(
                ExerciseRecord(exerciseID: id, status: .completed,
                               startedAt: exerciseStartedAt, completedAt: .now)
            )
        case .sessionCompleted:
            audio?.play(.sessionDone)
            haptics?.fire(.success)
        case .paused: isPaused = true
        case .resumed: isPaused = false
        }
    }
}
