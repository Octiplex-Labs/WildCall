import Foundation
import SwiftData

/// TOFU-pinned publisher key for a third-party pack id. When a third-party
/// pack is first imported via URL, the user is shown the publisher's key
/// fingerprint and confirms trust; the public key bytes are then pinned to
/// the pack id here. Subsequent imports/updates of the same pack id MUST
/// match this key : a mismatch is reported as a security failure.
@Model
public final class TrustedKeyRecord {
    @Attribute(.unique) public var packId: String
    public var publicKey: Data           // 32-byte raw Ed25519 public key
    public var fingerprint: String       // cached SHA-256 fingerprint for display
    public var pinnedAt: Date
    public var sourceURL: String?        // URL the pack was first imported from (informational)

    public init(
        packId: String,
        publicKey: Data,
        fingerprint: String,
        pinnedAt: Date,
        sourceURL: String? = nil
    ) {
        self.packId = packId
        self.publicKey = publicKey
        self.fingerprint = fingerprint
        self.pinnedAt = pinnedAt
        self.sourceURL = sourceURL
    }
}

public struct TrustedKey: Hashable, Sendable, Identifiable {
    public var id: String { packId }
    public let packId: String
    public let publicKey: Data
    public let fingerprint: String
    public let pinnedAt: Date
    public let sourceURL: String?

    public init(
        packId: String,
        publicKey: Data,
        fingerprint: String,
        pinnedAt: Date,
        sourceURL: String? = nil
    ) {
        self.packId = packId
        self.publicKey = publicKey
        self.fingerprint = fingerprint
        self.pinnedAt = pinnedAt
        self.sourceURL = sourceURL
    }
}

extension TrustedKeyRecord {
    public func toValue() -> TrustedKey {
        TrustedKey(
            packId: packId,
            publicKey: publicKey,
            fingerprint: fingerprint,
            pinnedAt: pinnedAt,
            sourceURL: sourceURL
        )
    }

    public static func from(_ key: TrustedKey) -> TrustedKeyRecord {
        TrustedKeyRecord(
            packId: key.packId,
            publicKey: key.publicKey,
            fingerprint: key.fingerprint,
            pinnedAt: key.pinnedAt,
            sourceURL: key.sourceURL
        )
    }
}
