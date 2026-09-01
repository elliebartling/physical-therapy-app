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
}
