import Foundation
import SwiftData

/// Activation state for an installed pack. The actual rules contributed by
/// the pack live in the `BlockRuleRecord` table with `source = pack:<id>`.
@Model
public final class PackRecord {
    @Attribute(.unique) public var id: String
    public var version: String
    public var country: String
    public var enabled: Bool
    public var installedAt: Date

    public init(
        id: String,
        version: String,
        country: String,
        enabled: Bool,
        installedAt: Date
    ) {
        self.id = id
        self.version = version
        self.country = country
        self.enabled = enabled
        self.installedAt = installedAt
    }
}

public struct InstalledPack: Hashable, Sendable, Identifiable {
    public let id: String
    public let version: String
    public let country: String
    public let enabled: Bool
    public let installedAt: Date

    public init(
        id: String,
        version: String,
        country: String,
        enabled: Bool,
        installedAt: Date
    ) {
        self.id = id
        self.version = version
        self.country = country
        self.enabled = enabled
        self.installedAt = installedAt
    }
}

extension PackRecord {
    public func toValue() -> InstalledPack {
        InstalledPack(
            id: id,
            version: version,
            country: country,
            enabled: enabled,
            installedAt: installedAt
        )
    }

    public static func from(_ pack: InstalledPack) -> PackRecord {
        PackRecord(
            id: pack.id,
            version: pack.version,
            country: pack.country,
            enabled: pack.enabled,
            installedAt: pack.installedAt
        )
    }
}
