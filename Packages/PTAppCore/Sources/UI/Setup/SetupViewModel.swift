import Foundation
import UIKit
import Observation
import DataKit
import ParsingKit
import MediaKit
import os

private let logger = Logger(subsystem: "PTAppCore", category: "setup")

@MainActor
@Observable
public final class SetupViewModel {
    /// `parsing` carries the message to show while the routine is being read.
    /// `reviewing` shows what a new sheet changes before it replaces the current routine.
    public enum Phase: Equatable {
        case idle, parsing(String), editing, reviewing(RoutineChanges), saved, failed(String)
    }

    /// The routine a new sheet would replace.
    public struct CurrentRoutine: Equatable {
        public let name: String
        public let phase: Int
        public let exercises: [ExerciseSpec]
    }

    private let routineRepo: RoutineRepository
    private let parser: RoutineParser
    private let matcher: ExerciseMatcher
    private let matchTimeout: Duration

    public var phase: Phase = .idle
    public var draft: ParsedRoutine = .init(name: "My routine", exercises: [])
    public var editorVM: RoutineEditorViewModel?
    /// Set when there's already a routine, so this is an update rather than a first setup.
    public private(set) var current: CurrentRoutine?

    public var isReplacing: Bool { current != nil }

    /// `matchTimeout` caps how long picture matching may hold up the editor.
    public init(
        routineRepo: RoutineRepository,
        parser: RoutineParser = .init(),
        matcher: ExerciseMatcher = .init(),
        // Provisional: no on-device measurement yet. One inference per exercise, effectively
        // serialised, each with a ~6.2 KB widened prompt. Exceeding it leaves exercises
        // `.unmatched` (retryable from the picker). If it proves too slow, batch into one
        // call or fill matches in after the editor appears; don't keep raising this.
        matchTimeout: Duration = .seconds(20)
    ) {
        self.routineRepo = routineRepo
        self.parser = parser
        self.matcher = matcher
        self.matchTimeout = matchTimeout
        do {
            if let routine = try routineRepo.fetchActive() {
                current = CurrentRoutine(name: routine.name, phase: routine.phase,
                                         exercises: routine.orderedExercises.map { ExerciseSpec($0) })
            }
        } catch {
            // Without the current routine there's nothing to compare against; saving still replaces it.
            logger.error("Loading the current routine failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func parse(_ image: UIImage) async {
        await parse([image])
    }

    /// Scanned pages or picked photos, in order, read as one routine.
    public func parse(_ images: [UIImage]) async {
        guard !images.isEmpty else {
            phase = .failed("We couldn't open those photos. Try picking them again — or enter your routine manually.")
            return
        }
        let single = images.count == 1
        phase = .parsing(single ? "Reading your handout…" : "Reading \(images.count) pages…")
        await run(
            { [parser] in try await parser.parse(images) },
            noTextMessage: single
                ? "We couldn't read that photo. Try again with more light and the page held flat — or enter your routine manually."
                : "We couldn't read those photos. Try again with more light and the pages held flat — or enter your routine manually."
        )
    }

    /// Picked files (PDFs, images, text), in order, read as one routine.
    public func parse(fileURLs: [URL]) async {
        guard !fileURLs.isEmpty else { return }
        phase = .parsing(fileURLs.count == 1 ? "Reading your file…" : "Reading \(fileURLs.count) files…")
        await run(
            { [parser] in try await parser.parse(fileURLs: fileURLs) },
            noTextMessage: "We couldn't find any text in that. Try a clearer copy — or enter your routine manually."
        )
    }

    /// The Files picker couldn't hand the files over.
    public func fileImportFailed(_ error: Error) {
        logger.error("File import failed: \(String(describing: error), privacy: .public)")
        phase = .failed("We couldn't open that file. Try picking it again — or enter your routine manually.")
    }

    /// A spoken or typed description of the routine.
    public func parse(transcript: String) async {
        phase = .parsing("Turning that into a routine…")
        await run(
            { [parser] in try await parser.parse(transcript: transcript) },
            noTextMessage: "We didn't catch any exercises in that. Try describing them again — or enter your routine manually."
        )
    }

    public func startManual() {
        draft = .init(name: "My routine", exercises: [])
        editorVM = RoutineEditorViewModel(parsed: draft)
        phase = .editing
    }

    /// Back to choosing a source, e.g. after a failed read.
    public func startOver() {
        draft = .init(name: "My routine", exercises: [])
        editorVM = nil
        phase = .idle
    }

    /// The editor's Save: review the changes first when replacing a routine, otherwise save.
    public func save() {
        if let editorVM { draft = editorVM.snapshot() }
        if let current {
            let changes = RoutineChanges(from: current.exercises,
                                         to: draft.toRoutine().orderedExercises.map { ExerciseSpec($0) })
            phase = .reviewing(changes)
        } else {
            confirm()
        }
    }

    /// Back from the review to the editor, keeping the edits.
    public func backToEditing() {
        phase = .editing
    }

    /// Saves the draft as the active routine, reporting a failure rather than dropping it.
    public func confirm() {
        do {
            try commit()
        } catch {
            logger.error("Saving the routine failed: \(String(describing: error), privacy: .public)")
            phase = .failed("We couldn't save your routine. Try again — your current routine hasn't changed.")
        }
    }

    public func commit() throws {
        if let editorVM { draft = editorVM.snapshot() }
        try routineRepo.replaceActive(with: draft.toRoutine())
        phase = .saved
    }

    private func run(
        _ work: () async throws -> ParsedRoutine,
        noTextMessage: String
    ) async {
        do {
            var parsed = try await work()
            let (exercises, imported) = await withSuggestedArt(parsed.exercises)
            parsed.exercises = exercises
            draft = parsed
            let editor = RoutineEditorViewModel(parsed: parsed)
            editor.importedSuggestions = imported
            editorVM = editor
            phase = .editing
        } catch {
            draft = .init(name: "My routine", exercises: [])
            if case ParsingError.noTextFound = error {
                phase = .failed(noTextMessage)
            } else if case ParsingError.unreadableFile = error {
                phase = .failed("We couldn't open that file. Try a PDF, a photo or a text file — or enter your routine manually.")
            } else {
                logger.error("Routine parse failed: \(String(describing: error), privacy: .public)")
                phase = .failed("Something went wrong reading that. Try again, or enter your routine manually.")
            }
        }
    }

    private enum MatchEvent: Sendable {
        case matched(Int, MatchResult)
        case timedOut
        case cancelled
    }

    /// Suggests a picture for every exercise, concurrently. This never fails the import:
    /// anything that doesn't finish in time stays `.unmatched` (never matched, so a later
    /// retry is still possible) and the exercises keep their order.
    private func withSuggestedArt(
        _ exercises: [ParsedRoutine.ParsedExercise]
    ) async -> ([ParsedRoutine.ParsedExercise], [UUID: ImportedSuggestions]) {
        guard !exercises.isEmpty else { return (exercises, [:]) }
        let matcher = matcher
        let timeout = matchTimeout
        let requests = exercises.enumerated().map { (index: $0.offset, name: $0.element.name, notes: $0.element.notes) }

        let results: [Int: MatchResult] = await withTaskGroup(of: MatchEvent.self) { group in
            for request in requests {
                group.addTask {
                    let result = await matcher.match(name: request.name, notes: request.notes)
                    return .matched(request.index, result)
                }
            }
            group.addTask {
                // Fires only if matching is still running at the deadline.
                do { try await Task.sleep(for: timeout) } catch { return .cancelled }
                return .timedOut
            }
            var found: [Int: MatchResult] = [:]
            var pending = requests.count
            loop: while pending > 0, let event = await group.next() {
                switch event {
                case .matched(let index, let result):
                    found[index] = result
                    pending -= 1
                case .timedOut:
                    logger.error("Picture matching timed out; leaving the rest unmatched")
                    break loop
                case .cancelled:
                    continue
                }
            }
            group.cancelAll()
            return found
        }

        var matched = exercises
        var imported: [UUID: ImportedSuggestions] = [:]
        for (index, result) in results where matched.indices.contains(index) && matched[index].art == .unmatched {
            matched[index].art = result.choice
            imported[matched[index].id] = ImportedSuggestions(
                name: matched[index].name, notes: matched[index].notes, result: result)
        }
        return (matched, imported)
    }
}
