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
    /// `parsing` carries the message to show while the routine is being read.
    public enum Phase: Equatable { case idle, parsing(String), editing, saved, failed(String) }

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
            let parsed = try await work()
            draft = parsed
            editorVM = RoutineEditorViewModel(parsed: parsed)
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
}
