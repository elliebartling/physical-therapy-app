import Foundation

/// One labelled block of instruction prose exactly as the PT handout wrote it
/// ("Setup", "Movement", "Tip", or whatever heading the sheet used).
///
/// Everything in a `HowToSection` came off the sheet; the app never writes one.
/// It lives in `Exercise.sheetHowTo`, deliberately apart from `Exercise.notes`,
/// which is shown beside the running timer.
public struct HowToSection: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let heading: String
    public let body: String

    public init(id: UUID = UUID(), heading: String, body: String) {
        self.id = id
        self.heading = heading
        self.body = body
    }
}
