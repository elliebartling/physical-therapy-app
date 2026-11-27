import Foundation
import Observation
import DataKit
import HistoryKit
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
        /// Getting into position for the next exercise: a countdown, or nil to wait for a tap.
        case transition(seconds: Int?)
    }

    /// The exercise coming up, shown during a transition.
    public struct UpNext: Equatable, Sendable {
        public let name: String
        public let prescription: String
        public let isOptional: Bool
    }

    private let engine: SessionEngine
    private let routine: Routine
    private let sessionRepo: SessionRepository
    private let audio: AudioCueService?
    private let haptics: HapticService?
    private let health: HealthRecorder?
    private let ratingTiming: RatingTiming
    private let countdownHaptics: Bool
    private let speech: SpeechService?
    private let announcesNext: Bool
    /// Exercises already done or covered today, left out of this session.
    private let alreadyDone: Set<UUID>

    public private(set) var currentExerciseName = ""
    public private(set) var currentNotes = ""
    public private(set) var exerciseIndex = 0
    public private(set) var totalExercises = 0
    public private(set) var currentSet: Int = 0
    public private(set) var totalSets: Int = 0
    public private(set) var currentSide: Side = .both
    /// The current exercise is an extra that can be skipped without leaving the day partial.
    public private(set) var currentIsOptional = false
    /// The next exercise, while getting ready for it.
    public private(set) var upNext: UpNext?
    public private(set) var display: Display = .starting
    /// When the current `display` began; drives the draining timer field.
    public private(set) var displayStartedAt: Date = .now
    public private(set) var isPaused = false
    /// When the current pause began; the timer field holds still at this moment.
    public private(set) var pausedAt: Date?
    public private(set) var isComplete = false
    public private(set) var resumeWindowExpired = false
    public private(set) var endedEarly = false

    /// Asks how the exercise just finished felt (only when rating after each one).
    public struct RatingPrompt: Equatable, Identifiable {
        public let id: UUID          // the exercise record being rated
        public let exerciseName: String
    }
    public private(set) var ratingPrompt: RatingPrompt?

    private var sessionRecord: SessionRecord
    private var currentExercise: Exercise?
    private var exerciseStartedAt: Date = .now
    private var backgroundedAt: Date?
    /// The Apple Health save started when the session ended, if any.
    @ObservationIgnored private(set) var healthSave: Task<Void, Never>?

    public init(routine: Routine, sessionRepo: SessionRepository,
                clock: Clock = SystemClock(), audio: AudioCueService? = AudioCueService(),
                haptics: HapticService? = HapticService(),
                health: HealthRecorder? = HealthRecorder(),
                ratingTiming: RatingTiming = .load(),
                skipping: Set<UUID> = [],
                countdownHaptics: Bool = SessionPreferences.countdownHaptics(),
                transition: SessionTransition = .none,
                speech: SpeechService? = nil,
                announcesNext: Bool = SessionPreferences.announcesNext()) {
        self.routine = routine
        self.speech = speech
        self.announcesNext = announcesNext
        self.alreadyDone = skipping
        self.countdownHaptics = countdownHaptics
        self.engine = SessionEngine(routine: routine, clock: clock, skipping: skipping, transition: transition)
        self.sessionRepo = sessionRepo
        self.audio = audio
        self.haptics = haptics
        self.health = health
        self.ratingTiming = ratingTiming
        self.sessionRecord = SessionRecord(routineID: routine.id, startedAt: .now)
    }

    public var isResting: Bool {
        if case .rest = display { return true }
        return false
    }

    /// Between exercises, getting ready for the next one.
    public var isTransitioning: Bool {
        if case .transition = display { return true }
        return false
    }

    /// Ready for the next exercise: ends the pause before it.
    public func startNext() async { try? await engine.completeCurrentSet() }

    /// What's said aloud as an exercise comes up, e.g. "Next: Bird Dog. 3 sets of 45 seconds on each side."
    static func announcement(for exercise: Exercise, isFirst: Bool) -> String {
        var text = (isFirst ? "First up: " : "Next: ") + exercise.name + ". "
        switch exercise.target {
        case let .repsSets(reps, sets):
            text += "\(sets) \(sets == 1 ? "set" : "sets") of \(reps)"
        case let .timeSets(seconds, sets):
            text += "\(sets) \(sets == 1 ? "set" : "sets") of \(spoken(seconds: seconds))"
        }
        switch exercise.side {
        case .alternating: text += " on each side"
        case .left: text += " on the left"
        case .right: text += " on the right"
        case .both: break
        }
        text += "."
        if exercise.isOptional { text += " It's optional." }
        return text
    }

    /// "45 seconds", "1 minute", "1 minute 30 seconds".
    static func spoken(seconds: Int) -> String {
        let minutes = seconds / 60
        let rest = seconds % 60
        let secondsText = "\(rest) \(rest == 1 ? "second" : "seconds")"
        guard minutes > 0 else { return secondsText }
        let minutesText = "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        return rest == 0 ? minutesText : "\(minutesText) \(secondsText)"
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
        saveToHealth(endedAt: finishedAt, finished: true)
    }

    public func pause() { engine.pause() }
    public func resume() { engine.resume() }
    public func completeCurrentSet() async { try? await engine.completeCurrentSet() }
    public func skipCurrentSet() async { try? await engine.skipCurrentSet() }
    /// Leaves out the rest of the current exercise, e.g. an optional one.
    public func skipCurrentExercise() async { try? await engine.skipCurrentExercise() }

    /// Every required exercise is done, here or earlier today, so ending now completes the day.
    public var canFinishNow: Bool {
        let doneHere = Set(sessionRecord.exerciseRecords.filter { $0.status == .completed }.map(\.exerciseID))
        return DayProgress.coversRequired(routine.exercises, done: alreadyDone.union(doneHere))
    }

    /// Ends the session as complete, once only optional exercises are left.
    public func finishNow() {
        guard !isComplete, canFinishNow else { return }
        engine.pause()
        let finishedAt = Date.now
        sessionRecord.completedAt = finishedAt
        try? sessionRepo.insert(sessionRecord)
        isComplete = true
        saveToHealth(endedAt: finishedAt, finished: true)
    }

    /// A light tap on each of the last three seconds of a hold or rest.
    public func timerTicked(from previous: Int, to remaining: Int) {
        guard countdownHaptics,
              Self.isCountdownTick(display: display, isPaused: isPaused, from: previous, to: remaining) else { return }
        haptics?.fire(.lightTick)
    }

    static func isCountdownTick(display: Display, isPaused: Bool, from previous: Int, to remaining: Int) -> Bool {
        guard !isPaused, remaining < previous, (1...3).contains(remaining) else { return false }
        switch display {
        case .hold, .rest: return true
        case .transition(let seconds): return seconds != nil
        case .reps, .starting: return false
        }
    }

    /// The session's record, for the summary once it's complete.
    public var record: SessionRecord { sessionRecord }

    /// Rates the exercise the current prompt is about, and closes the prompt.
    public func rate(_ rating: ExerciseRating) {
        guard let prompt = ratingPrompt else { return }
        sessionRecord.exerciseRecords.first { $0.id == prompt.id }?.rating = rating
        ratingPrompt = nil
    }

    public func dismissRatingPrompt() { ratingPrompt = nil }

    /// Stops the session and keeps what was done as a partial session (no `completedAt`).
    public func endEarly() {
        guard !isComplete else { return }
        engine.pause()
        endedEarly = true
        try? sessionRepo.insert(sessionRecord)
        isComplete = true
        saveToHealth(endedAt: .now, finished: false)
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
            saveToHealth(endedAt: bg, finished: false)
        }
    }

    /// Saves the session to Apple Health: a finished one always, a partial one
    /// only if at least one exercise was done.
    ///
    /// Reads the record now and hands plain values to the save, which runs on
    /// its own: the view, and with it `run()`, goes away once the session is
    /// complete, and the record mustn't be touched after its context is gone.
    private func saveToHealth(endedAt: Date, finished: Bool) {
        guard let health, finished || !sessionRecord.exerciseRecords.isEmpty else { return }
        let start = sessionRecord.startedAt
        healthSave = Task { await health.record(start: start, end: endedAt, wasLoggedLater: false) }
    }

    private func handle(_ event: PhaseEvent) {
        switch event {
        case .sessionStarted: break
        case .exerciseStarted(let id, let index, let total):
            currentExercise = routine.exercises.first { $0.id == id }
            currentExerciseName = currentExercise?.name ?? ""
            currentNotes = currentExercise?.notes ?? ""
            currentIsOptional = currentExercise?.isOptional ?? false
            upNext = nil
            if index == 0, announcesNext, let currentExercise {
                speech?.speak(Self.announcement(for: currentExercise, isFirst: true))
            }
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
            let record = ExerciseRecord(exerciseID: id, status: .completed,
                                        startedAt: exerciseStartedAt, completedAt: .now)
            sessionRecord.exerciseRecords.append(record)
            if ratingTiming == .afterEach {
                ratingPrompt = RatingPrompt(id: record.id, exerciseName: currentExerciseName)
            }
        case let .transition(nextID, seconds):
            if let next = routine.exercises.first(where: { $0.id == nextID }) {
                upNext = UpNext(name: next.name,
                                prescription: Prescription.text(target: next.target, side: next.side),
                                isOptional: next.isOptional)
                if announcesNext { speech?.speak(Self.announcement(for: next, isFirst: false)) }
            }
            show(.transition(seconds: seconds))
            haptics?.fire(.lightTick)
        case .exerciseSkipped(let id):
            sessionRecord.exerciseRecords.append(
                ExerciseRecord(exerciseID: id, status: .skipped, startedAt: exerciseStartedAt)
            )
        case .sessionCompleted:
            audio?.play(.sessionDone)
            haptics?.fire(.success)
        case .paused:
            isPaused = true
            pausedAt = .now
        case .resumed:
            isPaused = false
            // Shift the start by the pause so the timer carries on from where it stopped.
            if let pausedAt { displayStartedAt += Date.now.timeIntervalSince(pausedAt) }
            pausedAt = nil
        }
    }

    private func show(_ newDisplay: Display) {
        display = newDisplay
        displayStartedAt = .now
    }
}
