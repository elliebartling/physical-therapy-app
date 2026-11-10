import Foundation
import Observation
import ParsingKit

@MainActor
@Observable
public final class RoutineEditorViewModel {
    public var name: String
    public var exercises: [ParsedRoutine.ParsedExercise]

    public init(name: String, exercises: [ParsedRoutine.ParsedExercise]) {
        self.name = name
        self.exercises = exercises
    }

    public convenience init(parsed: ParsedRoutine) {
        self.init(name: parsed.name, exercises: parsed.exercises)
    }

    public func addExercise() {
        exercises.append(.init(name: "New exercise", reps: 10, sets: 3,
                               durationSec: nil, restSec: 30, side: "both", notes: ""))
    }
    public func remove(at offsets: IndexSet) { exercises.remove(atOffsets: offsets) }
    public func move(fromOffsets: IndexSet, toOffset: Int) {
        exercises.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    public func snapshot() -> ParsedRoutine { .init(name: name, exercises: exercises) }
}
