import Foundation
import SwiftData

@Model
public final class Asset {
    public enum Kind: String, Codable, Sendable { case image, video }

    @Attribute(.unique) public var id: UUID
    public var kind: Kind
    public var urlString: String

    public init(id: UUID = UUID(), kind: Kind, urlString: String) {
        self.id = id
        self.kind = kind
        self.urlString = urlString
    }
}
