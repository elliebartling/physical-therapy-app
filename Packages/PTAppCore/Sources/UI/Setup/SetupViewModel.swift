import Foundation
import UIKit
import Observation
import DataKit
import ParsingKit

@MainActor
@Observable
public final class SetupViewModel {
    public enum Phase: Equatable { case idle, parsing, editing, saved, failed(String) }

    private let routineRepo: RoutineRepository
    private let parser: RoutineParser

    public var phase: Phase = .idle
    public var draft: ParsedRoutine = .init(name: "My routine", exercises: [])
    public var editorVM: RoutineEditorViewModel?

    public init(routineRepo: RoutineRepository, parser: RoutineParser = .init()) {
        self.routineRepo = routineRepo
        self.parser = parser
    }

    public func parse(_ image: UIImage) async {
        phase = .parsing
        do {
            let parsed = try await parser.parse(image)
            draft = parsed
            editorVM = RoutineEditorViewModel(parsed: parsed)
            phase = .editing
        } catch {
            draft = .init(name: "My routine", exercises: [])
            phase = .failed(error.localizedDescription)
        }
    }

    public func startManual() {
        draft = .init(name: "My routine", exercises: [])
        editorVM = RoutineEditorViewModel(parsed: draft)
        phase = .editing
    }

    public func commit() throws {
        if let editorVM { draft = editorVM.snapshot() }
        try routineRepo.replaceActive(with: draft.toRoutine())
        phase = .saved
    }
}
