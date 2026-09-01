import Foundation
import UIKit
import Observation
import DataKit
import ParsingKit
import os

private let logger = Logger(subsystem: "PTAppCore", category: "setup")

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
            if case ParsingError.noTextFound = error {
                phase = .failed("We couldn't read that photo. Try again with more light and the page held flat — or enter your routine manually.")
            } else {
                logger.error("Routine parse failed: \(String(describing: error), privacy: .public)")
                phase = .failed("Something went wrong reading that photo. Try again, or enter your routine manually.")
            }
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
