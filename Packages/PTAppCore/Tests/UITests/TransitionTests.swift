import XCTest
import SwiftData
import DataKit
import ParsingKit
import SessionKit
@testable import UI

@MainActor
final class TransitionTests: XCTestCase {
    func test_announcement_saysWhatsNextAndHowMuch() {
        let birdDog = Exercise(name: "Bird Dog", target: .timeSets(seconds: 45, sets: 3), restSeconds: 30, side: .alternating)
        XCTAssertEqual(SessionViewModel.announcement(for: birdDog, isFirst: false),
                       "Next: Bird Dog. 3 sets of 45 seconds on each side.")

        let bridges = Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 1), restSeconds: 0, side: .both)
        XCTAssertEqual(SessionViewModel.announcement(for: bridges, isFirst: true), "First up: Bridges. 1 set of 10.")

        let stretch = Exercise(name: "Stretch", target: .timeSets(seconds: 90, sets: 2), restSeconds: 0, side: .left,
                               isOptional: true)
        XCTAssertEqual(SessionViewModel.announcement(for: stretch, isFirst: false),
                       "Next: Stretch. 2 sets of 1 minute 30 seconds on the left. It's optional.")
    }

    func test_spokenDurations() {
        XCTAssertEqual(SessionViewModel.spoken(seconds: 1), "1 second")
        XCTAssertEqual(SessionViewModel.spoken(seconds: 60), "1 minute")
        XCTAssertEqual(SessionViewModel.spoken(seconds: 125), "2 minutes 5 seconds")
    }

    func test_preferences_default_toTenSecondsAndSayingWhatsNext() {
        let name = "TransitionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(SessionPreferences.transitionSeconds(in: defaults), 10)
        XCTAssertTrue(SessionPreferences.announcesNext(in: defaults))
        defaults.set(0, forKey: SessionPreferences.transitionSecondsKey)
        XCTAssertEqual(SessionPreferences.transitionSeconds(in: defaults), 0)
    }

    func test_aRoutinesOwnPause_survivesEditingAndANewSheet() throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = RoutineRepository(context: container.mainContext)
        let routine = Routine(name: "Hips", exercises: [
            Exercise(name: "Bridges", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both, order: 0),
        ])
        try repo.save(routine)

        let editor = RoutineEditorViewModel(parsed: ParsedRoutine(routine: routine))
        XCTAssertNil(editor.transitionSeconds)
        editor.transitionSeconds = 0
        editor.snapshot().apply(to: routine)
        XCTAssertEqual(routine.transitionSeconds, 0)

        try repo.replaceActive(with: Routine(name: "Hips", exercises: []))
        XCTAssertEqual(try repo.fetchActive()?.transitionSeconds, 0)
        _ = container
    }

    func test_viewModel_showsWhatsNext_duringAPause() async throws {
        let container = try ModelContainerFactory.inMemory()
        let sessionRepo = SessionRepository(context: container.mainContext)
        let routine = Routine(name: "T", exercises: [
            Exercise(name: "Plank", target: .timeSets(seconds: 1, sets: 1), restSeconds: 0, side: .both, order: 0),
            Exercise(name: "Wall sit", target: .timeSets(seconds: 30, sets: 2), restSeconds: 0, side: .both, order: 1,
                     isOptional: true),
        ])
        let vm = SessionViewModel(routine: routine, sessionRepo: sessionRepo, clock: TestClock(), audio: nil,
                                  haptics: nil, health: nil, countdownHaptics: false, transition: .manual)
        let run = Task { await vm.run() }
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(vm.display, .transition(seconds: nil))
        XCTAssertEqual(vm.upNext, SessionViewModel.UpNext(name: "Wall sit", prescription: "2×30s", isOptional: true))

        await vm.startNext()
        await run.value
        XCTAssertTrue(vm.isComplete)
        _ = container
    }
}
