import Foundation

/// JSON shape for the root pack index hosted at the Octiplex repo.
/// Single source of truth listing every pack available via remote sync.
public struct PackIndex: Codable, Equatable, Sendable {
    public let version: Int
    public let updatedAt: String  // ISO 8601 string, informational
    public let packs: [PackIndexEntry]

    public init(version: Int, updatedAt: String, packs: [PackIndexEntry]) {
        self.version = version
        self.updatedAt = updatedAt
        self.packs = packs
    }
}

public struct PackIndexEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let version: String
    public let country: String
    public let kind: PackKind
    public let url: URL

    public init(id: String, version: String, country: String, kind: PackKind, url: URL) {
        self.id = id
        self.version = version
        self.country = country
        self.kind = kind
        self.url = url
    }
}
