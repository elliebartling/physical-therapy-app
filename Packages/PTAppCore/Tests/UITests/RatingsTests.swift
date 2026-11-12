import XCTest
import SwiftData
import DataKit
import SessionKit
@testable import UI

@MainActor
final class RatingsTests: XCTestCase {
    private var container: ModelContainer!
    private var routineRepo: RoutineRepository!
    private var sessionRepo: SessionRepository!
    private var routine: Routine!

    override func setUp() async throws {
        container = try ModelContainerFactory.inMemory()
        routineRepo = RoutineRepository(context: container.mainContext)
        sessionRepo = SessionRepository(context: container.mainContext)
        routine = Routine(name: "Knee", exercises: [
            Exercise(name: "Bridges", target: .timeSets(seconds: 1, sets: 1), restSeconds: 0, side: .both, order: 0),
            Exercise(name: "Wall sit", target: .timeSets(seconds: 1, sets: 1), restSeconds: 0, side: .both, order: 1),
        ])
        try routineRepo.save(routine)
    }

    override func tearDown() async throws {
        routine = nil; sessionRepo = nil; routineRepo = nil; container = nil
    }

    private func runSession(rating timing: RatingTiming) async throws -> SessionViewModel {
        let vm = SessionViewModel(routine: routine, sessionRepo: sessionRepo, clock: TestClock(),
                                  audio: nil, haptics: nil, health: nil, ratingTiming: timing)
        await vm.run()
        try await Task.sleep(nanoseconds: 50_000_000) // drain the last events
        return vm
    }

    // MARK: Setting

    func test_ratingTiming_defaultsToAtTheEnd_andReadsWhatWasSaved() {
        let name = "RatingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(RatingTiming.load(from: defaults), .atEnd)
        defaults.set(RatingTiming.afterEach.rawValue, forKey: RatingTiming.storageKey)
        XCTAssertEqual(RatingTiming.load(from: defaults), .afterEach)
    }

    // MARK: After each exercise

    func test_afterEach_asksAboutTheExerciseJustFinished_andSavesTheRating() async throws {
        let vm = try await runSession(rating: .afterEach)

        XCTAssertEqual(vm.ratingPrompt?.exerciseName, "Wall sit")
        vm.rate(.hard)

        XCTAssertNil(vm.ratingPrompt)
        let saved = try XCTUnwrap(try sessionRepo.fetchAll().first)
        let wallSit = routine.orderedExercises[1].id
        XCTAssertEqual(saved.exerciseRecords.first { $0.exerciseID == wallSit }?.rating, .hard)
    }

    func test_atTheEndOrOff_neverInterruptsTheSession() async throws {
        for timing in [RatingTiming.atEnd, .off] {
            let vm = try await runSession(rating: timing)
            XCTAssertNil(vm.ratingPrompt, "\(timing) shouldn't prompt mid-session")
        }
    }

    func test_dismissingThePrompt_leavesTheExerciseUnrated() async throws {
        let vm = try await runSession(rating: .afterEach)
        vm.dismissRatingPrompt()
        XCTAssertNil(vm.ratingPrompt)
        XCTAssertTrue(vm.record.exerciseRecords.allSatisfy { $0.rating == nil })
    }

    // MARK: Summary

    func test_summary_listsWhatWasDone_inRoutineOrder_keepingRatingsAlreadyGiven() async throws {
        let vm = try await runSession(rating: .afterEach)
        vm.rate(.easy) // Wall sit, rated during the session

        let summary = SessionSummaryViewModel(record: vm.record, routine: routine, sessionRepo: sessionRepo,
                                              ratingTiming: .afterEach)

        XCTAssertTrue(summary.showsRatings)
        XCTAssertEqual(summary.items.map(\.name), ["Bridges", "Wall sit"])
        XCTAssertEqual(summary.items.map(\.rating), [nil, .easy])
        XCTAssertEqual(summary.unratedCount, 1)
    }

    func test_summary_savesRatingsPainAndNote() async throws {
        let vm = try await runSession(rating: .atEnd)
        let summary = SessionSummaryViewModel(record: vm.record, routine: routine, sessionRepo: sessionRepo,
                                              ratingTiming: .atEnd)
        summary.items[0].rating = .painful
        summary.painLevel = 4
        summary.note = "  Left knee clicked on bridges \n"

        XCTAssertTrue(summary.save())

        let saved = try XCTUnwrap(try sessionRepo.fetchAll().first)
        let bridges = routine.orderedExercises[0].id
        XCTAssertEqual(saved.exerciseRecords.first { $0.exerciseID == bridges }?.rating, .painful)
        XCTAssertEqual(saved.painLevel, 4)
        XCTAssertEqual(saved.note, "Left knee clicked on bridges")
        XCTAssertNil(summary.errorMessage)
    }

    func test_summary_leavesBlankAnswersEmpty_andHidesRatingsWhenOff() async throws {
        let vm = try await runSession(rating: .off)
        let summary = SessionSummaryViewModel(record: vm.record, routine: routine, sessionRepo: sessionRepo,
                                              ratingTiming: .off)
        XCTAssertFalse(summary.showsRatings)
        summary.note = "   "

        XCTAssertTrue(summary.save())

        let saved = try XCTUnwrap(try sessionRepo.fetchAll().first)
        XCTAssertNil(saved.painLevel)
        XCTAssertNil(saved.note)
        XCTAssertTrue(saved.exerciseRecords.allSatisfy { $0.rating == nil })
    }

    // MARK: Progress

    func test_progress_showsRatingsPainAndNote() async throws {
        let vm = try await runSession(rating: .afterEach)
        vm.rate(.hard) // Wall sit
        let summary = SessionSummaryViewModel(record: vm.record, routine: routine, sessionRepo: sessionRepo,
                                              ratingTiming: .afterEach)
        summary.painLevel = 2
        summary.note = "Felt strong"
        XCTAssertTrue(summary.save())

        let progress = ProgressViewModel(routineRepo: routineRepo, sessionRepo: sessionRepo)
        progress.refresh()

        let wallSit = routine.orderedExercises[1].id
        XCTAssertEqual(progress.exercise(id: wallSit)?.lastRating, .hard)
        XCTAssertEqual(progress.entries(forExercise: wallSit).first?.rating, .hard)
        let row = try XCTUnwrap(progress.months.first?.sessions.first)
        XCTAssertEqual(row.painLevel, 2)
        XCTAssertEqual(row.note, "Felt strong")
        XCTAssertEqual(row.items.map(\.rating), [nil, .hard])
    }
}
