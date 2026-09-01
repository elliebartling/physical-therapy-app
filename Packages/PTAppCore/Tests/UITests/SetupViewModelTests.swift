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
}
