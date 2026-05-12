import Foundation

public enum PackKind: String, Hashable, Sendable, Codable {
    case prefixes
    case preExpanded
}

public struct Pack: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: PackKind
    public let version: String
    public let country: String
    public let enabled: Bool
    public let installedAt: Date?
    public let manifestURL: URL
    public let signaturePublicKey: Data

    public init(
        id: String,
        kind: PackKind,
        version: String,
        country: String,
        enabled: Bool,
        installedAt: Date?,
        manifestURL: URL,
        signaturePublicKey: Data
    ) {
        self.id = id
        self.kind = kind
        self.version = version
        self.country = country
        self.enabled = enabled
        self.installedAt = installedAt
        self.manifestURL = manifestURL
        self.signaturePublicKey = signaturePublicKey
    }
}
