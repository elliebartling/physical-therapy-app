import Foundation
import SwiftData

public enum ModelContainerFactory {
    public static var allModelTypes: [any PersistentModel.Type] {
        [Routine.self, Exercise.self, Asset.self, SessionRecord.self, ExerciseRecord.self]
    }

    /// Production container — local persistence only. CloudKit is intentionally deferred to a later milestone.
    public static func production() throws -> ModelContainer {
        let config = ModelConfiguration("PTApp")
        return try ModelContainer(
            for: Routine.self, Exercise.self, Asset.self,
            SessionRecord.self, ExerciseRecord.self,
            configurations: config
        )
    }

    /// In-memory container for tests / previews.
    public static func inMemory() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Routine.self, Exercise.self, Asset.self,
            SessionRecord.self, ExerciseRecord.self,
            configurations: config
        )
    }
}
