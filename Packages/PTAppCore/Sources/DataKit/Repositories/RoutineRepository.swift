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

    public func replaceActive(with routine: Routine) throws {
        for old in try fetchAll() where old.isActive {
            old.isActive = false
        }
        routine.isActive = true
        context.insert(routine)
        try context.save()
    }
}
