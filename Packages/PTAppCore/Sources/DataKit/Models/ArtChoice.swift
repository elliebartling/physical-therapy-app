import Foundation

/// Which illustration an exercise shows.
public enum ArtChoice: Equatable, Sendable, Codable {
    /// Not yet matched to anything; the matcher may fill this in.
    case unmatched
    /// A bundled library illustration, by slug.
    case library(slug: String)
    /// The user chose to show no illustration.
    case none

    private static let libraryPrefix = "library:"

    /// Stable string form: `"unmatched"`, `"none"`, or `"library:<slug>"`.
    public var rawValue: String {
        switch self {
        case .unmatched: "unmatched"
        case .none: "none"
        case .library(let slug): Self.libraryPrefix + slug
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "unmatched":
            self = .unmatched
        case "none":
            self = .none
        case let value where value.hasPrefix(Self.libraryPrefix):
            let slug = String(value.dropFirst(Self.libraryPrefix.count))
            guard !slug.isEmpty else { return nil }
            self = .library(slug: slug)
        default:
            return nil
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = ArtChoice(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unknown ArtChoice raw value: \(raw)")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
