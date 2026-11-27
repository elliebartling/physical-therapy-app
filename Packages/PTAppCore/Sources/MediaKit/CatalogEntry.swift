import Foundation

/// One exercise in the bundled catalogue that pictures can be matched against.
public struct CatalogEntry: Codable, Sendable, Equatable, Identifiable {
    public let slug: String
    public let name: String
    public let equipment: String
    public let primaryMuscle: String
    public let secondaryMuscles: [String]
    public let isStretch: Bool

    public var id: String { slug }

    public init(
        slug: String,
        name: String,
        equipment: String,
        primaryMuscle: String,
        secondaryMuscles: [String],
        isStretch: Bool
    ) {
        self.slug = slug
        self.name = name
        self.equipment = equipment
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles
        self.isStretch = isStretch
    }
}
