import Foundation
import os

private let logger = Logger(subsystem: "PTAppCore", category: "media")

/// The bundled set of exercises (bodyweight and household-equipment only)
/// generated from the upstream workout-guide manifest.
public struct ExerciseCatalog: Sendable {
    public let entries: [CatalogEntry]

    public init(entries: [CatalogEntry]) {
        self.entries = entries
    }

    /// Decoded once from `catalog.json`. A missing or malformed resource
    /// degrades to an empty catalogue rather than trapping.
    public static let bundled: ExerciseCatalog = {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {
            logger.error("catalog.json is missing from the MediaKit bundle")
            return ExerciseCatalog(entries: [])
        }
        do {
            let data = try Data(contentsOf: url)
            let entries = try JSONDecoder().decode([CatalogEntry].self, from: data)
            return ExerciseCatalog(entries: entries)
        } catch {
            logger.error("Could not load catalog.json: \(error.localizedDescription, privacy: .public)")
            return ExerciseCatalog(entries: [])
        }
    }()

    public func entry(slug: String) -> CatalogEntry? {
        entries.first { $0.slug == slug }
    }
}
