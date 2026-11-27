import XCTest
import LiveSession
@testable import UI

@MainActor
final class LiveSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func test_aRunningHold_countsDownToItsEnd() {
        let state = SessionViewModel.liveState(display: .hold(seconds: 30), isPaused: false, startedAt: start,
                                               pausedAt: nil, title: "Bird Dog", detail: "SET 1/3 — LEFT SIDE",
                                               progress: 0.25)
        XCTAssertEqual(state.endsAt, start.addingTimeInterval(30))
        XCTAssertNil(state.remainingSeconds)
        XCTAssertNil(state.reps)
        XCTAssertFalse(state.isPaused)
        XCTAssertEqual(state.title, "Bird Dog")
        XCTAssertEqual(state.progress, 0.25)
    }

    func test_aPausedHold_freezesWhatsLeft() {
        let state = SessionViewModel.liveState(display: .rest(seconds: 20), isPaused: true, startedAt: start,
                                               pausedAt: start.addingTimeInterval(12.4), title: "Rest", detail: "",
                                               progress: 0)
        XCTAssertNil(state.endsAt, "a paused countdown doesn't tick")
        XCTAssertEqual(state.remainingSeconds, 8)
        XCTAssertTrue(state.isPaused)
    }

    func test_repsAndWaitingForMe_haveNothingToCount() {
        let reps = SessionViewModel.liveState(display: .reps(12), isPaused: false, startedAt: start, pausedAt: nil,
                                              title: "Bridges", detail: "SET 2/3", progress: 0)
        XCTAssertEqual(reps.reps, 12)
        XCTAssertNil(reps.endsAt)

        let waiting = SessionViewModel.liveState(display: .transition(seconds: nil), isPaused: false, startedAt: start,
                                                 pausedAt: nil, title: "Up next: Clams", detail: "2×15", progress: 0.5)
        XCTAssertNil(waiting.endsAt)
        XCTAssertNil(waiting.reps)

        let timedPause = SessionViewModel.liveState(display: .transition(seconds: 10), isPaused: false, startedAt: start,
                                                    pausedAt: nil, title: "Up next: Clams", detail: "2×15", progress: 0.5)
        XCTAssertEqual(timedPause.endsAt, start.addingTimeInterval(10))
    }

    func test_keepingGoingInTheBackground_isOnUntilTurnedOff() {
        let name = "LiveSessionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(SessionPreferences.keepsRunningInBackground(in: defaults))
        defaults.set(false, forKey: SessionPreferences.backgroundKey)
        XCTAssertFalse(SessionPreferences.keepsRunningInBackground(in: defaults))
    }

    func test_liveActivityButtons_reachTheRunningSession() {
        var received: [LiveSessionCommands.Command] = []
        LiveSessionCommands.shared.handler = { received.append($0) }
        defer { LiveSessionCommands.shared.handler = nil }

        LiveSessionCommands.shared.send(.togglePause)
        LiveSessionCommands.shared.send(.next)

        XCTAssertEqual(received.count, 2)
    }
}
