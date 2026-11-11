import Foundation
import Observation
import DataKit
import ParsingKit
import os

private let logger = Logger(subsystem: "PTAppCore", category: "edit-routine")

/// Edits the saved routine in place, so its session history stays attached.
@MainActor
@Observable
public final class EditRoutineViewModel {
    public let editor: RoutineEditorViewModel
    public private(set) var errorMessage: String?

    private let routine: Routine
    private let repo: RoutineRepository

    public init(routine: Routine, repo: RoutineRepository) {
        self.routine = routine
        self.repo = repo
        self.editor = RoutineEditorViewModel(parsed: ParsedRoutine(routine: routine))
    }

    /// Returns whether the changes were saved.
    @discardableResult
    public func save() -> Bool {
        let removed = editor.snapshot().apply(to: routine)
        do {
            try repo.saveEdits(to: routine, removing: removed)
            errorMessage = nil
            return true
        } catch {
            logger.error("Saving routine edits failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't save your changes. Try again."
            return false
        }
    }

    public func dismissError() { errorMessage = nil }
}
