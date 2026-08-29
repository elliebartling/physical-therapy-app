import Foundation
import SwiftData

@Model
public final class Routine {
    public var id: UUID
    public var name: String
    public var clinicianNotes: String?
    public var createdAt: Date
    public var isActive: Bool
    public var daysPerWeek: Int
    @Relationship(deleteRule: .cascade, inverse: \Exercise.routine)
    public var exercises: [Exercise]

    public init(
        id: UUID = UUID(),
        name: String,
        clinicianNotes: String? = nil,
        createdAt: Date = .now,
        isActive: Bool = true,
        daysPerWeek: Int = 7,
        exercises: [Exercise] = []
    ) {
        self.id = id
        self.name = name
        self.clinicianNotes = clinicianNotes
        self.createdAt = createdAt
        self.isActive = isActive
        self.daysPerWeek = daysPerWeek
        self.exercises = exercises
    }

    public var orderedExercises: [Exercise] {
        exercises.sorted { $0.orderIndex < $1.orderIndex }
    }
}

@Model
public final class Exercise {
    public var id: UUID
    public var name: String
    public var details: String?
    public var orderIndex: Int
    public var sets: Int
    public var reps: Int?
    public var holdSeconds: Int?
    public var restSeconds: Int
    public var isPerSide: Bool
    public var equipment: String?
    public var routine: Routine?

    public init(
        id: UUID = UUID(),
        name: String,
        details: String? = nil,
        orderIndex: Int = 0,
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
        self.orderIndex = orderIndex
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

@Model
public final class SessionLog {
    public var id: UUID
    public var routineID: UUID
    public var routineName: String
    public var startedAt: Date
    public var endedAt: Date?
    public var source: String
    public var painLevel: Int?
    public var savedToHealthKit: Bool
    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.session)
    public var exerciseLogs: [ExerciseLog]

    public init(
        id: UUID = UUID(),
        routineID: UUID,
        routineName: String,
        startedAt: Date,
        endedAt: Date? = nil,
        source: String = "phone",
        painLevel: Int? = nil,
        savedToHealthKit: Bool = false,
        exerciseLogs: [ExerciseLog] = []
    ) {
        self.id = id
        self.routineID = routineID
        self.routineName = routineName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.source = source
        self.painLevel = painLevel
        self.savedToHealthKit = savedToHealthKit
        self.exerciseLogs = exerciseLogs
    }

    public var duration: TimeInterval {
        (endedAt ?? startedAt).timeIntervalSince(startedAt)
    }

    public var completedExerciseCount: Int {
        exerciseLogs.filter { !$0.skipped }.count
    }
}

@Model
public final class ExerciseLog {
    public var id: UUID
    public var exerciseID: UUID
    public var name: String
    public var targetSets: Int
    public var completedSets: Int
    public var totalReps: Int
    public var totalHoldSeconds: Int
    public var skipped: Bool
    public var session: SessionLog?

    public init(
        id: UUID = UUID(),
        exerciseID: UUID,
        name: String,
        targetSets: Int,
        completedSets: Int,
        totalReps: Int = 0,
        totalHoldSeconds: Int = 0,
        skipped: Bool = false
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.name = name
        self.targetSets = targetSets
        self.completedSets = completedSets
        self.totalReps = totalReps
        self.totalHoldSeconds = totalHoldSeconds
        self.skipped = skipped
    }
}
