import XCTest
@testable import UI

private final class FakeDictation: Dictating, @unchecked Sendable {
    var granted = true
    var partials: [String] = []
    var failStart = false
    private(set) var stopCount = 0

    func requestAccess() async -> Bool { granted }

    func start() throws -> AsyncThrowingStream<String, Error> {
        if failStart { throw DictationError.recognizerUnavailable }
        let partials = partials
        return AsyncThrowingStream { continuation in
            for p in partials { continuation.yield(p) }
            continuation.finish()
        }
    }

    func stop() { stopCount += 1 }
}

@MainActor
final class BrainDumpViewModelTests: XCTestCase {
    func test_listening_showsTheGrowingTranscript() async {
        let fake = FakeDictation()
        fake.partials = ["Clamshells", "Clamshells three sets", "Clamshells three sets of twelve"]
        let vm = BrainDumpViewModel(dictation: fake)

        await vm.startListening()
        await vm.waitForListeningToEnd()

        XCTAssertEqual(vm.transcript, "Clamshells three sets of twelve")
        XCTAssertFalse(vm.isListening)
        XCTAssertTrue(vm.canSubmit)
    }

    func test_listeningAgain_appendsToWhatIsAlreadyThere() async {
        let fake = FakeDictation()
        fake.partials = ["Then bridges"]
        let vm = BrainDumpViewModel(dictation: fake)
        vm.transcript = "Clamshells, three sets of twelve. "

        await vm.startListening()
        await vm.waitForListeningToEnd()

        XCTAssertEqual(vm.transcript, "Clamshells, three sets of twelve. Then bridges")
    }

    func test_accessDenied_explainsAndDoesNotListen() async {
        let fake = FakeDictation()
        fake.granted = false
        let vm = BrainDumpViewModel(dictation: fake)

        await vm.startListening()

        XCTAssertFalse(vm.isListening)
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_unavailableRecognizer_suggestsTyping() async {
        let fake = FakeDictation()
        fake.failStart = true
        let vm = BrainDumpViewModel(dictation: fake)

        await vm.startListening()

        XCTAssertFalse(vm.isListening)
        XCTAssertEqual(vm.errorMessage?.contains("type"), true)
    }

    func test_canSubmit_ignoresWhitespace() {
        let vm = BrainDumpViewModel(dictation: FakeDictation())
        vm.transcript = "  \n "
        XCTAssertFalse(vm.canSubmit)
    }
}
