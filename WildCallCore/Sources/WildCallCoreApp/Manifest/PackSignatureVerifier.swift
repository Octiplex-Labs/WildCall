import CryptoKit
import Foundation

public struct PackSignatureVerifier: Sendable {
    public var verify: @Sendable (
        _ manifest: Data,
        _ signature: Data,
        _ publicKey: Data
    ) -> Bool

    public init(verify: @escaping @Sendable (Data, Data, Data) -> Bool) {
        self.verify = verify
    }
}

extension PackSignatureVerifier {
    public static let live = PackSignatureVerifier { manifest, signature, publicKey in
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
            return false
        }
        return key.isValidSignature(signature, for: manifest)
    }
}

public enum OctiplexTrust {
    /// Ed25519 public key (32 bytes raw) of the Octiplex publisher identity.
    /// Embedded packs and Octiplex-distributed remote packs must be signed
    /// with the corresponding private key. Third-party packs follow TOFU
    /// (see Phase 4c).
    ///
    /// Fingerprint (SHA-256 prefix): F0:75:1B:D4:92:C1:ED:2A
    /// Generated 2026-05-20 via `swift Tools/wildcall-sign/generate-key.swift`.
    /// The matching private key lives out-of-band; never commit it.
    public static let publicKey: Data = Data([
        0xcb, 0x79, 0x74, 0xed, 0x75, 0x40, 0x89, 0x79,
        0x0a, 0x97, 0xaf, 0xb6, 0x1d, 0x3a, 0xa8, 0xd7,
        0xa6, 0x83, 0x73, 0xd8, 0x9a, 0x53, 0x13, 0x61,
        0x5a, 0x35, 0x8f, 0x45, 0x3f, 0x99, 0x3a, 0xe4,
    ])

    /// SHA-256 fingerprint of a public key, formatted as colon-separated hex
    /// pairs (8 pairs = 16 hex chars). For TOFU display.
    public static func fingerprint(of publicKey: Data) -> String {
        let digest = SHA256.hash(data: publicKey)
        let hex = digest.prefix(8)
            .map { String(format: "%02X", $0) }
        return hex.joined(separator: ":")
    }

    public static var isConfigured: Bool {
        publicKey != Data(repeating: 0, count: 32)
    }
}
