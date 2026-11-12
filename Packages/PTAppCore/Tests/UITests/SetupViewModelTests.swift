import XCTest
import UIKit
import DataKit
import ParsingKit
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
}
