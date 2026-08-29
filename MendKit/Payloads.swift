import Foundation

/// Codable snapshots of routines used for the workout player, watch sync,
/// and the pre-save review/editing flow after screenshot extraction.

public struct RoutinePayload: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var daysPerWeek: Int
    public var clinicianNotes: String?
    public var exercises: [ExercisePayload]

    public init(
        id: UUID = UUID(),
        name: String = "",
        daysPerWeek: Int = 7,
        clinicianNotes: String? = nil,
        exercises: [ExercisePayload] = []
    ) {
        self.id = id
        self.name = name
        self.daysPerWeek = daysPerWeek
        self.clinicianNotes = clinicianNotes
        self.exercises = exercises
    }

    /// Rough duration estimate: timed steps at face value, rep steps at ~3s per rep.
    public var estimatedSeconds: Int {
        exercises.reduce(0) { total, exercise in
            let sides = exercise.isPerSide ? 2 : 1
            let work: Int
            if let hold = exercise.holdSeconds, hold > 0 {
                work = hold
            } else {
                work = (exercise.reps ?? 10) * 3
            }
            let steps = max(1, exercise.sets) * sides
            return total + steps * (work + exercise.restSeconds)
        }
    }
}

public struct ExercisePayload: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var details: String?
    public var sets: Int
    public var reps: Int?
    public var holdSeconds: Int?
    public var restSeconds: Int
    public var isPerSide: Bool
    public var equipment: String?

    public init(
        id: UUID = UUID(),
        name: String = "",
        details: String? = nil,
        sets: Int = 3,
        reps: Int? = 10,
        holdSeconds: Int? = nil,
        restSeconds: Int = 30,
        isPerSide: Bool = false,
        equipment: String? = nil
    ) {
        self.id = id
        self.name = name
        self.details = details
        self.sets = sets
        self.reps = reps
        self.holdSeconds = holdSeconds
        self.restSeconds = restSeconds
        self.isPerSide = isPerSide
        self.equipment = equipment
    }

    public var isTimed: Bool { (holdSeconds ?? 0) > 0 }

    public var goalDescription: String {
        let base: String
        if let holdSeconds, holdSeconds > 0 {
            base = "\(sets) × \(Format.duration(holdSeconds)) hold"
        } else if let reps, reps > 0 {
            base = "\(sets) × \(reps) reps"
        } else {
            base = "\(sets) sets"
        }
        return isPerSide ? base + " · each side" : base
    }
}

public struct CompletedSessionPayload: Codable, Sendable {
    public var id: UUID
    public var routineID: UUID
    public var routineName: String
    public var startedAt: Date
    public var endedAt: Date
    public var source: String
    public var exercises: [CompletedExercisePayload]

    public init(
        id: UUID = UUID(),
        routineID: UUID,
        routineName: String,
        startedAt: Date,
        endedAt: Date,
        source: String,
        exercises: [CompletedExercisePayload]
    ) {
        self.id = id
        self.routineID = routineID
        self.routineName = routineName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.source = source
        self.exercises = exercises
    }
}

public struct CompletedExercisePayload: Codable, Sendable {
    public var exerciseID: UUID
    public var name: String
    public var targetSets: Int
    public var completedSets: Int
    public var totalReps: Int
    public var totalHoldSeconds: Int
    public var skipped: Bool

    public init(
        exerciseID: UUID,
        name: String,
        targetSets: Int,
        completedSets: Int,
        totalReps: Int,
        totalHoldSeconds: Int,
        skipped: Bool
    ) {
        self.exerciseID = exerciseID
        self.name = name
        self.targetSets = targetSets
        self.completedSets = completedSets
        self.totalReps = totalReps
        self.totalHoldSeconds = totalHoldSeconds
        self.skipped = skipped
    }
}

// MARK: - Model conversions

public extension Routine {
    var payload: RoutinePayload {
        RoutinePayload(
            id: id,
            name: name,
            daysPerWeek: daysPerWeek,
            clinicianNotes: clinicianNotes,
            exercises: orderedExercises.map(\.payload)
        )
    }
}

public extension Exercise {
    var payload: ExercisePayload {
        ExercisePayload(
            id: id,
            name: name,
            details: details,
            sets: sets,
            reps: reps,
            holdSeconds: holdSeconds,
            restSeconds: restSeconds,
            isPerSide: isPerSide,
            equipment: equipment
        )
    }
}

public extension SessionLog {
    convenience init(from payload: CompletedSessionPayload, painLevel: Int? = nil, savedToHealthKit: Bool = false) {
        self.init(
            id: payload.id,
            routineID: payload.routineID,
            routineName: payload.routineName,
            startedAt: payload.startedAt,
            endedAt: payload.endedAt,
            source: payload.source,
            painLevel: painLevel,
            savedToHealthKit: savedToHealthKit,
            exerciseLogs: payload.exercises.map { exercise in
                ExerciseLog(
                    exerciseID: exercise.exerciseID,
                    name: exercise.name,
                    targetSets: exercise.targetSets,
                    completedSets: exercise.completedSets,
                    totalReps: exercise.totalReps,
                    totalHoldSeconds: exercise.totalHoldSeconds,
                    skipped: exercise.skipped
                )
            }
        )
    }
}
