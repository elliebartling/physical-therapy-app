import XCTest
import UIKit
import SwiftData
import DataKit
import ParsingKit
import MediaKit
@testable import UI

@MainActor
final class SetupViewModelTests: XCTestCase {
    func test_parseAndSave_persistsRoutineAsActive() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = RoutineRepository(context: container.mainContext)
        let canned = ParsedRoutine(name: "Knee", exercises: [
            .init(name: "Squat", reps: 10, sets: 3, durationSec: nil, restSec: 30, side: "both", notes: "")
        ])
        let parser = RoutineParser(ocr: OCRService(), extractors: [StubExtractor(result: canned)])
        let vm = SetupViewModel(routineRepo: repo, parser: parser)

        vm.draft = canned
        try vm.commit()

        XCTAssertEqual(try repo.fetchActive()?.name, "Knee")
        _ = container  // hold container alive
    }

    func test_parse_unreadablePhoto_failsWithActionableMessage() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = RoutineRepository(context: container.mainContext)
        let canned = ParsedRoutine(name: "Knee", exercises: [])
        let parser = RoutineParser(ocr: OCRService(), extractors: [StubExtractor(result: canned)])
        let vm = SetupViewModel(routineRepo: repo, parser: parser)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let blank = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }

        await vm.parse(blank)

        guard case .failed(let message) = vm.phase else {
            return XCTFail("expected .failed, got \(vm.phase)")
        }
        XCTAssertTrue(message.contains("light"))
        _ = container
    }

    func test_parseTranscript_opensEditorWithExtractedRoutine() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = RoutineRepository(context: container.mainContext)
        let canned = ParsedRoutine(name: "Knee", exercises: [
            .init(name: "Clamshells", reps: 12, sets: 3, durationSec: nil, restSec: 30, side: "both", notes: "")
        ])
        let parser = RoutineParser(ocr: OCRService(), extractors: [StubExtractor(result: canned)])
        let vm = SetupViewModel(routineRepo: repo, parser: parser)

        await vm.parse(transcript: "Clamshells, three sets of twelve each side")

        XCTAssertEqual(vm.phase, .editing)
        XCTAssertEqual(vm.editorVM?.exercises.map(\.name), ["Clamshells"])
        _ = container
    }

    func test_parseTranscript_blank_failsWithActionableMessage() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = RoutineRepository(context: container.mainContext)
        let parser = RoutineParser(extractors: [StubExtractor(result: .init(name: "K", exercises: []))])
        let vm = SetupViewModel(routineRepo: repo, parser: parser)

        await vm.parse(transcript: "   ")

        guard case .failed(let message) = vm.phase else {
            return XCTFail("expected .failed, got \(vm.phase)")
        }
        XCTAssertTrue(message.contains("describing"))
        _ = container
    }

    func test_parseFile_opensEditorWithExtractedRoutine() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = RoutineRepository(context: container.mainContext)
        let canned = ParsedRoutine(name: "Knee", exercises: [
            .init(name: "Bridges", reps: 10, sets: 3, durationSec: nil, restSec: 30, side: "both", notes: "")
        ])
        let vm = SetupViewModel(routineRepo: repo,
                                parser: RoutineParser(extractors: [StubExtractor(result: canned)]))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try "Bridges 3 x 10".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        await vm.parse(fileURLs: [file])

        XCTAssertEqual(vm.phase, .editing)
        XCTAssertEqual(vm.editorVM?.exercises.map(\.name), ["Bridges"])
        _ = container
    }

    func test_parseUnsupportedFile_failsWithActionableMessage() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = RoutineRepository(context: container.mainContext)
        let vm = SetupViewModel(routineRepo: repo,
                                parser: RoutineParser(extractors: [StubExtractor(result: .init(name: "K", exercises: []))]))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        try Data([0x50, 0x4B]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        await vm.parse(fileURLs: [file])

        guard case .failed(let message) = vm.phase else {
            return XCTFail("expected .failed, got \(vm.phase)")
        }
        XCTAssertTrue(message.contains("PDF"))
        _ = container
    }

    func test_startOver_returnsToSourceChoice() throws {
        let container = try ModelContainerFactory.inMemory()
        let vm = SetupViewModel(routineRepo: RoutineRepository(context: container.mainContext))
        vm.startManual()

        vm.startOver()

        XCTAssertEqual(vm.phase, .idle)
        XCTAssertNil(vm.editorVM)
        _ = container
    }

    // MARK: - A new sheet for an existing routine

    private func phase1(in repo: RoutineRepository) throws {
        try repo.save(Routine(name: "Knee", exercises: [
            Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both, order: 0),
            Exercise(name: "Wall sit", target: .timeSets(seconds: 30, sets: 3), restSeconds: 30, side: .both, order: 1),
        ]))
    }

    private let newSheet = ParsedRoutine(name: "Knee", exercises: [
        .init(name: "Bridges", reps: 15, sets: 3, durationSec: nil, restSec: 30, side: "both", notes: ""),
        .init(name: "Step ups", reps: 10, sets: 2, durationSec: nil, restSec: 30, side: "both", notes: ""),
    ])

    func test_firstRoutine_savesWithoutReview() throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = RoutineRepository(context: container.mainContext)
        let vm = SetupViewModel(routineRepo: repo)
        XCTAssertFalse(vm.isReplacing)
        vm.draft = newSheet

        vm.save()

        XCTAssertEqual(vm.phase, .saved)
        XCTAssertEqual(try repo.fetchActive()?.exercises.count, 2)
        _ = container
    }

    func test_newSheet_showsWhatChanged_beforeReplacing() throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = RoutineRepository(context: container.mainContext)
        try phase1(in: repo)
        let vm = SetupViewModel(routineRepo: repo)
        XCTAssertTrue(vm.isReplacing)
        XCTAssertEqual(vm.current?.phase, 1)
        vm.draft = newSheet

        vm.save()

        guard case .reviewing(let changes) = vm.phase else {
            return XCTFail("expected .reviewing, got \(vm.phase)")
        }
        XCTAssertEqual(changes.items.map(\.name), ["Bridges", "Step ups", "Wall sit"])
        XCTAssertEqual(changes.items.map(\.kind), [.changed, .added, .removed])
        // Nothing is replaced until it's confirmed.
        XCTAssertEqual(try repo.fetchActive()?.phase, 1)
        _ = container
    }

    func test_confirmingTheReview_replacesWithTheNextPhase() throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = RoutineRepository(context: container.mainContext)
        try phase1(in: repo)
        let vm = SetupViewModel(routineRepo: repo)
        vm.draft = newSheet
        vm.save()

        vm.confirm()

        XCTAssertEqual(vm.phase, .saved)
        let active = try XCTUnwrap(repo.fetchActive())
        XCTAssertEqual(active.phase, 2)
        XCTAssertEqual(active.orderedExercises.map(\.name), ["Bridges", "Step ups"])
        _ = container
    }

    func test_backFromReview_returnsToTheEditorWithEditsKept() throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = RoutineRepository(context: container.mainContext)
        try phase1(in: repo)
        let vm = SetupViewModel(routineRepo: repo)
        vm.draft = newSheet
        vm.editorVM = RoutineEditorViewModel(parsed: newSheet)
        vm.phase = .editing
        vm.save()

        vm.backToEditing()

        XCTAssertEqual(vm.phase, .editing)
        XCTAssertEqual(vm.editorVM?.exercises.map(\.name), ["Bridges", "Step ups"])
        _ = container
    }

    // MARK: - Picture matching during import

    private let twoExercises = ParsedRoutine(name: "Back", exercises: [
        .init(name: "Bird dog", reps: 10, sets: 3, durationSec: nil, restSec: 30, side: "both", notes: ""),
        .init(name: "Cat cow", reps: 10, sets: 3, durationSec: nil, restSec: 30, side: "both", notes: ""),
    ])

    private let strongAndWeak = ParsedRoutine(name: "Back", exercises: [
        .init(name: "Bird dog", reps: 10, sets: 3, durationSec: nil, restSec: 30, side: "both", notes: ""),
        .init(name: "Slant board gastrocnemius stretch", reps: 10, sets: 3, durationSec: nil, restSec: 30, side: "both", notes: ""),
    ])

    private func makeVM(_ canned: ParsedRoutine, ranker: any CandidateRanker,
                        timeout: Duration = .seconds(5)) throws -> (SetupViewModel, ModelContainer) {
        let container = try ModelContainerFactory.inMemory()
        let repo = RoutineRepository(context: container.mainContext)
        let vm = SetupViewModel(routineRepo: repo,
                                parser: RoutineParser(extractors: [StubExtractor(result: canned)]),
                                matcher: ExerciseMatcher(ranker: ranker),
                                matchTimeout: timeout)
        return (vm, container)
    }

    private func textFile() throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try "Bird dog 3 x 10".write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func test_parseKeepsTheMatchersAlternativesForThePicker() async throws {
        // A weak name makes the matcher offer the whole catalogue to the ranker, so all three
        // slugs survive its shortlist filter and the last two become alternatives.
        let (vm, container) = try makeVM(strongAndWeak,
                                         ranker: StubRanker(slugs: ["bird-dog", "dead-bug", "clamshell"]))
        await vm.parse(transcript: "Bird dog and a calf stretch")
        let editor = try XCTUnwrap(vm.editorVM)
        let weak = try XCTUnwrap(editor.exercises.first { $0.name.hasPrefix("Slant board") })
        let kept = try XCTUnwrap(editor.importedSuggestions[weak.id])
        XCTAssertEqual(kept.name, weak.name)
        XCTAssertEqual(kept.result.choice, weak.art)
        XCTAssertEqual(kept.result.choice, .library(slug: "bird-dog"))
        XCTAssertEqual(kept.result.alternatives, ["dead-bug", "clamshell"])
        _ = container
    }

    func test_parseAssignsArtToEveryDraftExercise() async throws {
        // StubRanker answers "bird-dog" for both, but the matcher discards slugs outside the
        // shortlist it offered, so "Cat cow" gets nothing usable from the ranker and falls
        // back to stage 1, which finds cat-cow-stretch. That is why the second differs.
        let (vm, container) = try makeVM(twoExercises, ranker: StubRanker(slugs: ["bird-dog"]))
        await vm.parse(transcript: "Bird dog and cat cow")
        XCTAssertEqual(vm.phase, .editing)
        XCTAssertEqual(vm.draft.exercises.map(\.art), [.library(slug: "bird-dog"), .library(slug: "cat-cow-stretch")])
        XCTAssertEqual(vm.editorVM?.snapshot().exercises.map(\.art),
                       [.library(slug: "bird-dog"), .library(slug: "cat-cow-stretch")])
        _ = container
    }

    func test_fileImportAssignsArt() async throws {
        let (vm, container) = try makeVM(twoExercises, ranker: StubRanker(slugs: ["bird-dog"]))
        let file = try textFile()
        defer { try? FileManager.default.removeItem(at: file) }
        await vm.parse(fileURLs: [file])
        XCTAssertEqual(vm.draft.exercises.first?.art, .library(slug: "bird-dog"))
        _ = container
    }

    func test_transcriptAssignsArt() async throws {
        let (vm, container) = try makeVM(twoExercises, ranker: StubRanker(slugs: ["bird-dog"]))
        await vm.parse(transcript: "Bird dog and cat cow, three sets of ten")
        XCTAssertEqual(vm.draft.exercises.first?.art, .library(slug: "bird-dog"))
        _ = container
    }

    func test_matchingFailureStillReachesTheEditor() async throws {
        let (vm, container) = try makeVM(strongAndWeak, ranker: ThrowingRanker())
        await vm.parse(transcript: "Bird dog and slant board")
        XCTAssertEqual(vm.phase, .editing)
        XCTAssertNotNil(vm.editorVM)
        XCTAssertEqual(vm.draft.exercises.map(\.name), ["Bird dog", "Slant board gastrocnemius stretch"])
        // The failed ranker falls back to stage 1: a strong name still gets its picture,
        // a weak one stays retryable. A failed lookup is never the "no picture" decision.
        XCTAssertEqual(vm.draft.exercises.map(\.art), [.library(slug: "bird-dog"), .unmatched])
        _ = container
    }

    func test_unavailableModelLeavesWeakExercisesRetryableNotNone() async throws {
        let (vm, container) = try makeVM(strongAndWeak, ranker: StubRanker(slugs: ["bird-dog"], isAvailable: false))
        await vm.parse(transcript: "Bird dog and slant board")
        XCTAssertEqual(vm.phase, .editing)
        XCTAssertEqual(vm.draft.exercises.map(\.art), [.library(slug: "bird-dog"), .unmatched])
        _ = container
    }

    func test_slowMatchingTimesOutAndLeavesExercisesRetryable() async throws {
        // The first exercise answers at once, the second never does: matching ran, and the
        // deadline released the editor with the slow one still retryable.
        let (vm, container) = try makeVM(twoExercises, ranker: HangsOnCatCowRanker(), timeout: .milliseconds(200))
        await vm.parse(transcript: "Bird dog and cat cow")
        XCTAssertEqual(vm.phase, .editing)
        XCTAssertEqual(vm.draft.exercises.map(\.art), [.library(slug: "bird-dog"), .unmatched])
        _ = container
    }

    func test_resultsLandOnTheirOwnExercise() async throws {
        let (vm, container) = try makeVM(twoExercises, ranker: SlugByNameRanker())
        await vm.parse(transcript: "Bird dog and cat cow")
        XCTAssertEqual(vm.draft.exercises.map(\.art), [.library(slug: "bird-dog"), .library(slug: "cat-cow-stretch")])
        _ = container
    }

    func test_manualStartNeverInvokesTheMatcher() async throws {
        let ranker = RecordingRanker(slugs: ["bird-dog"])
        let (vm, container) = try makeVM(twoExercises, ranker: ranker)
        vm.draft = twoExercises
        vm.startManual()
        XCTAssertEqual(vm.phase, .editing)
        XCTAssertTrue(vm.draft.exercises.isEmpty)
        let calls = await ranker.lastCandidateCount
        XCTAssertEqual(calls, 0)
        _ = container
    }
}

/// Answers "bird-dog" at once, but never answers "Cat cow" until cancelled.
private struct HangsOnCatCowRanker: CandidateRanker {
    let isAvailable = true
    func rank(name: String, notes: String, candidates: [ScoredCandidate]) async throws -> [String] {
        if name == "Cat cow" { try await Task.sleep(for: .seconds(60)) }
        return ["bird-dog"]
    }
}

/// Answers per exercise, and the first one slowly, so completion order differs from list order.
private struct SlugByNameRanker: CandidateRanker {
    let isAvailable = true
    func rank(name: String, notes: String, candidates: [ScoredCandidate]) async throws -> [String] {
        if name == "Bird dog" { try await Task.sleep(for: .milliseconds(100)) }
        return [name == "Bird dog" ? "bird-dog" : "cat-cow-stretch"]
    }
}
