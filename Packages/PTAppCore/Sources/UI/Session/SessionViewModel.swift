import Foundation
import Observation
import DataKit
import SessionKit

@MainActor
@Observable
public final class SessionViewModel {
    /// What the big number on screen is showing.
    public enum Display: Equatable, Sendable {
        case starting
        case hold(seconds: Int)
        case reps(Int)
        case rest(seconds: Int)
    }

    private let engine: SessionEngine
    private let routine: Routine
    private let sessionRepo: SessionRepository
    private let audio: AudioCueService?
    private let haptics: HapticService?
    private let health: HealthRecorder?

    public private(set) var currentExerciseName = ""
    public private(set) var currentNotes = ""
    public private(set) var exerciseIndex = 0
    public private(set) var totalExercises = 0
    public private(set) var currentSet: Int = 0
    public private(set) var totalSets: Int = 0
    public private(set) var currentSide: Side = .both
    public private(set) var display: Display = .starting
    /// When the current `display` began; drives the draining timer field.
    public private(set) var displayStartedAt: Date = .now
    public private(set) var isPaused = false
    public private(set) var isComplete = false
    public private(set) var resumeWindowExpired = false
    public private(set) var endedEarly = false

    private var sessionRecord: SessionRecord
    private var currentExercise: Exercise?
    private var exerciseStartedAt: Date = .now
    private var backgroundedAt: Date?
    /// The Apple Health save started when the session ended, if any.
    @ObservationIgnored private(set) var healthSave: Task<Void, Never>?

    public init(routine: Routine, sessionRepo: SessionRepository,
                clock: Clock = SystemClock(), audio: AudioCueService? = AudioCueService(),
                haptics: HapticService? = HapticService(),
                health: HealthRecorder? = HealthRecorder()) {
        self.routine = routine
        self.engine = SessionEngine(routine: routine, clock: clock)
        self.sessionRepo = sessionRepo
        self.audio = audio
        self.haptics = haptics
        self.health = health
        self.sessionRecord = SessionRecord(routineID: routine.id, startedAt: .now)
    }

    public var isResting: Bool {
        if case .rest = display { return true }
        return false
    }

    public func run() async {
        let listener = Task { @MainActor in
            for await event in engine.events { self.handle(event) }
        }
        defer { listener.cancel() }
        do {
            try await engine.start()
        } catch {
            return // cancelled: the view went away mid-session
        }
        // Ending early or an expired resume window already saved this session as partial.
        guard !isComplete else { return }
        let finishedAt = Date.now
        sessionRecord.completedAt = finishedAt
        try? sessionRepo.insert(sessionRecord)
        isComplete = true
        // Not tied to this task: the view, and with it run(), goes away once complete.
        healthSave = Task { await recordInHealth(endedAt: finishedAt, finished: true) }
    }

    public func pause() { engine.pause() }
    public func resume() { engine.resume() }
    public func completeCurrentSet() async { try? await engine.completeCurrentSet() }
    public func skipCurrentSet() async { try? await engine.skipCurrentSet() }

    /// Stops the session and keeps what was done as a partial session (no `completedAt`).
    public func endEarly() {
        guard !isComplete else { return }
        engine.pause()
        endedEarly = true
        try? sessionRepo.insert(sessionRecord)
        isComplete = true
        let endedAt = Date.now
        healthSave = Task { await recordInHealth(endedAt: endedAt, finished: false) }
    }

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
            healthSave = Task { await recordInHealth(endedAt: bg, finished: false) }
        }
    }

    /// Saves the session to Apple Health: a finished one always, a partial one
    /// only if at least one exercise was done.
    private func recordInHealth(endedAt: Date, finished: Bool) async {
        guard let health, finished || !sessionRecord.exerciseRecords.isEmpty else { return }
        await health.record(start: sessionRecord.startedAt, end: endedAt, wasLoggedLater: false)
    }

    private func handle(_ event: PhaseEvent) {
        switch event {
        case .sessionStarted: break
        case .exerciseStarted(let id, let index, let total):
            currentExercise = routine.exercises.first { $0.id == id }
            currentExerciseName = currentExercise?.name ?? ""
            currentNotes = currentExercise?.notes ?? ""
            totalSets = currentExercise?.target.totalSets ?? 0
            exerciseIndex = index
            totalExercises = total
            exerciseStartedAt = .now
        case .setStarted(let i, let total, let side):
            currentSet = i + 1
            totalSets = total
            currentSide = side
            switch currentExercise?.target {
            case .timeSets(let seconds, _): show(.hold(seconds: seconds))
            case .repsSets(let reps, _): show(.reps(reps))
            case nil: show(.starting)
            }
            audio?.play(.setStart)
            haptics?.fire(.mediumTick)
        case .rest(let seconds):
            show(.rest(seconds: seconds))
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

    private func show(_ newDisplay: Display) {
        display = newDisplay
        displayStartedAt = .now
    }
}
