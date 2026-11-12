import Foundation
import Observation
import DataKit
import os

private let logger = Logger(subsystem: "PTAppCore", category: "summary")

/// The optional summary after a session: catch-up ratings, pain, and a note for the PT.
@MainActor
@Observable
public final class SessionSummaryViewModel {
    public struct Item: Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public var rating: ExerciseRating?
    }

    public var items: [Item]
    /// Pain from 0 to 10; nil until the person sets it.
    public var painLevel: Int?
    public var note: String
    public private(set) var errorMessage: String?
    /// False when ratings are turned off, or nothing was done.
    public let showsRatings: Bool

    private let record: SessionRecord
    private let sessionRepo: SessionRepository

    public init(record: SessionRecord, routine: Routine?, sessionRepo: SessionRepository,
                ratingTiming: RatingTiming = .load()) {
        self.record = record
        self.sessionRepo = sessionRepo
        let exercises = routine?.exercises ?? []
        let names = Dictionary(exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let order = Dictionary(exercises.map { ($0.id, $0.order) }, uniquingKeysWith: { first, _ in first })
        self.items = record.exerciseRecords
            .filter { $0.status == .completed }
            .sorted { (order[$0.exerciseID] ?? .max, $0.startedAt) < (order[$1.exerciseID] ?? .max, $1.startedAt) }
            .map { Item(id: $0.id, name: names[$0.exerciseID] ?? "Exercise", rating: $0.rating) }
        self.painLevel = record.painLevel
        self.note = record.note ?? ""
        self.showsRatings = ratingTiming != .off && !items.isEmpty
    }

    public var unratedCount: Int { items.filter { $0.rating == nil }.count }

    /// Writes ratings, pain and note onto the saved session. Returns whether it worked.
    @discardableResult
    public func save() -> Bool {
        for item in items {
            record.exerciseRecords.first { $0.id == item.id }?.rating = item.rating
        }
        record.painLevel = painLevel.map { min(max($0, 0), 10) }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        record.note = trimmed.isEmpty ? nil : trimmed
        do {
            try sessionRepo.saveChanges()
            errorMessage = nil
            return true
        } catch {
            logger.error("Saving the session summary failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't save your notes. Try again."
            return false
        }
    }

    public func dismissError() { errorMessage = nil }
}
