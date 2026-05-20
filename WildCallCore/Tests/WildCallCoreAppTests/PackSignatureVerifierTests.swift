import CryptoKit
import Foundation
import Testing
@testable import WildCallCoreApp

@Suite struct PackSignatureVerifierTests {
    let verifier = PackSignatureVerifier.live

    @Test func verifiesGoodSignature() {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey.rawRepresentation
        let manifest = Data("{\"id\":\"fr.test\"}".utf8)
        let signature = try! privateKey.signature(for: manifest)
        #expect(verifier.verify(manifest, signature, publicKey) == true)
    }

    @Test func rejectsBadSignature() {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey.rawRepresentation
        let manifest = Data("{\"id\":\"fr.test\"}".utf8)
        var signature = try! privateKey.signature(for: manifest)
        signature[0] ^= 0xFF  // tamper
        #expect(verifier.verify(manifest, signature, publicKey) == false)
    }

    @Test func rejectsWrongPublicKey() {
        let signerKey = Curve25519.Signing.PrivateKey()
        let otherKey = Curve25519.Signing.PrivateKey()
        let manifest = Data("{\"id\":\"fr.test\"}".utf8)
        let signature = try! signerKey.signature(for: manifest)
        #expect(verifier.verify(manifest, signature, otherKey.publicKey.rawRepresentation) == false)
    }

    @Test func rejectsTamperedManifest() {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey.rawRepresentation
        let manifest = Data("{\"id\":\"fr.test\"}".utf8)
        let signature = try! privateKey.signature(for: manifest)
        let altered = Data("{\"id\":\"fr.evil\"}".utf8)
        #expect(verifier.verify(altered, signature, publicKey) == false)
    }

    @Test func rejectsMalformedPublicKey() {
        let signature = Data(repeating: 0, count: 64)
        let badKey = Data(repeating: 0xAA, count: 10)  // not 32 bytes
        #expect(verifier.verify(Data(), signature, badKey) == false)
    }

    @Test func fingerprintIsStableAndFormatted() {
        let key = Data(repeating: 0xAB, count: 32)
        let fp1 = OctiplexTrust.fingerprint(of: key)
        let fp2 = OctiplexTrust.fingerprint(of: key)
        #expect(fp1 == fp2)
        #expect(fp1.contains(":"))
        // 8 hex pairs separated by 7 colons = 23 chars total
        #expect(fp1.count == 23)
    }

    @Test func octiplexTrustIsUnconfiguredByDefault() {
        // Placeholder remains all zeros until Phase 4a C4 embeds the real key.
        #expect(OctiplexTrust.isConfigured == false)
    }
}
