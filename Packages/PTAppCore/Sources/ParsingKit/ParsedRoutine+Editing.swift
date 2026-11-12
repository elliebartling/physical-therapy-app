import Foundation
import DataKit

public extension ParsedRoutine {
    /// An editable draft of a saved routine. Exercise ids carry over, so applying
    /// the draft later updates those exercises instead of replacing them.
    init(routine: Routine) {
        self.init(name: routine.name, exercises: routine.orderedExercises.map(ParsedExercise.init(exercise:)))
    }

    /// Writes this draft onto `routine` in place. Exercises whose ids survive keep their
    /// identity (and so their session history); new drafts become new exercises.
    /// Returns the exercises the edit removed, for the caller to delete.
    @discardableResult
    func apply(to routine: Routine) -> [Exercise] {
        routine.name = name
        let existing = Dictionary(routine.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kept: [Exercise] = exercises.enumerated().map { index, draft in
            if let exercise = existing[draft.id] {
                exercise.name = draft.name
                exercise.target = draft.target
                exercise.restSeconds = draft.restSec
                exercise.side = draft.resolvedSide
                exercise.notes = draft.notes
                exercise.art = draft.art
                exercise.sheetHowTo = draft.sheetHowTo
                exercise.order = index
                return exercise
            }
            return Exercise(id: draft.id, name: draft.name, target: draft.target,
                            restSeconds: draft.restSec, side: draft.resolvedSide,
                            notes: draft.notes, order: index, art: draft.art,
                            sheetHowTo: draft.sheetHowTo)
        }
        let keptIDs = Set(kept.map(\.id))
        let removed = routine.exercises.filter { !keptIDs.contains($0.id) }
        routine.exercises = kept
        return removed
    }
}

extension ParsedRoutine.ParsedExercise {
    init(exercise: Exercise) {
        let reps: Int?
        let durationSec: Int?
        let sets: Int
        switch exercise.target {
        case .repsSets(let r, let s): reps = r; durationSec = nil; sets = s
        case .timeSets(let seconds, let s): reps = nil; durationSec = seconds; sets = s
        }
        self.init(id: exercise.id, name: exercise.name, reps: reps, sets: sets,
                  durationSec: durationSec, restSec: exercise.restSeconds,
                  side: exercise.side.rawValue, notes: exercise.notes, art: exercise.art,
                  sheetHowTo: exercise.sheetHowTo)
    }

    var target: ExerciseTarget {
        if let durationSec { return .timeSets(seconds: durationSec, sets: sets) }
        return .repsSets(reps: reps ?? 0, sets: sets)
    }

    var resolvedSide: Side { Side(rawValue: side.lowercased()) ?? .both }
}
