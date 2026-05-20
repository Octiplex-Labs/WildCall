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
    /// **Placeholder — replace via Phase 4a C4 once the key is generated.**
    public static let publicKey: Data = Data(repeating: 0, count: 32)

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
