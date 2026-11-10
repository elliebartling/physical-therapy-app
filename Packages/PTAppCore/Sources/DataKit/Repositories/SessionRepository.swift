import Foundation
import SwiftData

@MainActor
public final class SessionRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func insert(_ record: SessionRecord) throws {
        context.insert(record)
        try context.save()
    }

    public func fetchAll() throws -> [SessionRecord] {
        try context.fetch(
            FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        )
    }

    public func fetch(from start: Date, through end: Date) throws -> [SessionRecord] {
        let descriptor = FetchDescriptor<SessionRecord>(
            predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try context.fetch(descriptor)
    }

    public func mostRecent() throws -> SessionRecord? {
        var d = FetchDescriptor<SessionRecord>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
