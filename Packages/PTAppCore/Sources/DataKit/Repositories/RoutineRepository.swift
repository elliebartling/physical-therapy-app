import Foundation
import SwiftData

@MainActor
public final class RoutineRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func save(_ routine: Routine) throws {
        context.insert(routine)
        try context.save()
    }

    public func fetchActive() throws -> Routine? {
        var descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.isActive == true },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func fetchAll() throws -> [Routine] {
        try context.fetch(
            FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        )
    }

    /// Persists edits made to a saved routine in place, deleting exercises the edit removed.
    /// The routine keeps its id, so its session history stays attached.
    public func saveEdits(to routine: Routine, removing removed: [Exercise]) throws {
        for exercise in removed {
            context.delete(exercise)
        }
        try context.save()
    }

    /// Makes `routine` the active one, as the next phase of the current routine.
    /// The current routine is kept, inactive, so its sessions still read well. New exercises
    /// whose names match current ones continue their lineage, so history spans phases.
    public func replaceActive(with routine: Routine) throws {
        if let current = try fetchActive() {
            let currentExercises = current.orderedExercises
            let newExercises = routine.orderedExercises
            let changes = RoutineChanges(from: currentExercises.map { ExerciseSpec($0) },
                                         to: newExercises.map { ExerciseSpec($0) })
            for (newIndex, oldIndex) in changes.matches {
                newExercises[newIndex].lineageID = currentExercises[oldIndex].lineageID
            }
            routine.phase = current.phase + 1
            routine.previousVersionID = current.id
        }
        for old in try fetchAll() where old.isActive {
            old.isActive = false
        }
        routine.isActive = true
        context.insert(routine)
        try context.save()
    }
}
