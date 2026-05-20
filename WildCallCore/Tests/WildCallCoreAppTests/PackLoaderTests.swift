import CryptoKit
import Dependencies
import Foundation
import Testing
import IssueReporting
@testable import WildCallCoreApp

@Suite struct PackLoaderTests {
    let loader = PackLoader.live
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func loadsArcepSubsetFromManifest() {
        let manifest = PackManifest(
            id: "fr.arcep",
            version: "2026-05-13",
            country: "FR",
            kind: .prefixes,
            prefixes: ["+33162*", "+33163*", "+33568*"]
        )

        withDependencies {
            $0.uuid = .incrementing
            $0.wildcardParser = .live
        } operation: {
            let rules = loader.load(manifest, now)
            #expect(rules.count == 3)
            for rule in rules {
                #expect(rule.source == .pack(packId: "fr.arcep"))
                #expect(rule.action == .block)
                #expect(rule.countryCode == "FR")
                #expect(rule.createdAt == now)
                if case .prefix(let prefix) = rule.kind {
                    // FR national length = 9, 3 fixed nat digits → 6 wildcards.
                    #expect(prefix.wildcardLength == 6)
                } else {
                    Issue.record("expected .prefix rule, got \(rule.kind)")
                }
            }
        }
    }

    @Test func skipsMalformedPatternsAndReportsThem() {
        let manifest = PackManifest(
            id: "fr.broken",
            version: "0",
            country: "FR",
            kind: .prefixes,
            prefixes: ["+33162*", "absolutely_not_a_pattern*", "+33163*"]
        )

        withKnownIssue {
            let rules = withDependencies {
                $0.uuid = .incrementing
                $0.wildcardParser = .live
            } operation: {
                loader.load(manifest, now)
            }
            #expect(rules.count == 2)
            #expect(rules.allSatisfy { $0.source == .pack(packId: "fr.broken") })
        }
    }

    // MARK: - loadFromArchive

    @Test func loadFromArchiveHappyPath() {
        let signerKey = Curve25519.Signing.PrivateKey()
        let manifestJSON = """
        {
          "id": "test.signed",
          "version": "v1",
          "country": "FR",
          "kind": "prefixes",
          "prefixes": ["+33162*"]
        }
        """
        let manifestData = Data(manifestJSON.utf8)
        let signature = try! signerKey.signature(for: manifestData)
        let archive = try! PackArchive().write(.init(
            manifest: manifestData,
            signature: signature,
            payload: nil
        ))

        let result = withDependencies {
            $0.uuid = .incrementing
            $0.wildcardParser = .live
        } operation: {
            loader.loadFromArchive(archive, signerKey.publicKey.rawRepresentation, now)
        }

        switch result {
        case .success(let loaded):
            #expect(loaded.manifest.id == "test.signed")
            #expect(loaded.rules.count == 1)
            #expect(loaded.rules.first?.source == .pack(packId: "test.signed"))
        case .failure(let error):
            Issue.record("expected success, got \(error)")
        }
    }

    @Test func loadFromArchiveRejectsBadSignature() {
        let signerKey = Curve25519.Signing.PrivateKey()
        let otherKey = Curve25519.Signing.PrivateKey()
        let manifestData = Data("{\"id\":\"x\",\"version\":\"v1\",\"country\":\"FR\",\"kind\":\"prefixes\",\"prefixes\":[]}".utf8)
        let signature = try! signerKey.signature(for: manifestData)
        let archive = try! PackArchive().write(.init(
            manifest: manifestData,
            signature: signature,
            payload: nil
        ))

        // Verify with a different public key — should fail.
        let result = loader.loadFromArchive(archive, otherKey.publicKey.rawRepresentation, now)
        #expect(result == .failure(.signatureInvalid))
    }

    @Test func loadFromArchiveRejectsTamperedManifest() {
        let signerKey = Curve25519.Signing.PrivateKey()
        let original = Data("{\"id\":\"trusted\",\"version\":\"v1\",\"country\":\"FR\",\"kind\":\"prefixes\",\"prefixes\":[]}".utf8)
        let signature = try! signerKey.signature(for: original)

        // Build archive with a DIFFERENT manifest than the one the signature
        // covers — verification must fail.
        let tampered = Data("{\"id\":\"evil\",\"version\":\"v1\",\"country\":\"FR\",\"kind\":\"prefixes\",\"prefixes\":[]}".utf8)
        let archive = try! PackArchive().write(.init(
            manifest: tampered,
            signature: signature,
            payload: nil
        ))

        let result = loader.loadFromArchive(archive, signerKey.publicKey.rawRepresentation, now)
        #expect(result == .failure(.signatureInvalid))
    }

    @Test func loadFromArchiveRejectsCorruptedGzip() {
        let garbage = Data([0xFF, 0x00, 0x01, 0x02, 0x03])
        let result = loader.loadFromArchive(garbage, Data(repeating: 0, count: 32), now)
        if case .failure(.archiveRead(.decompressionFailed)) = result {
            // expected
        } else {
            Issue.record("expected .archiveRead(.decompressionFailed), got \(result)")
        }
    }

    @Test func loadFromArchiveRejectsMalformedManifestJSON() {
        let signerKey = Curve25519.Signing.PrivateKey()
        let manifestData = Data("not json at all".utf8)
        let signature = try! signerKey.signature(for: manifestData)
        let archive = try! PackArchive().write(.init(
            manifest: manifestData,
            signature: signature,
            payload: nil
        ))

        let result = loader.loadFromArchive(archive, signerKey.publicKey.rawRepresentation, now)
        if case .failure(.manifestDecode) = result {
            // expected
        } else {
            Issue.record("expected .manifestDecode, got \(result)")
        }
    }

    @Test func bypassesPerPatternQuotaThatWouldRejectUserInput() {
        // +33162* expands to 10⁶ entries — way above the default 10⁴ per-pattern
        // quota. The loader must override the quota internally and accept it.
        let manifest = PackManifest(
            id: "fr.demo",
            version: "0",
            country: "FR",
            kind: .prefixes,
            prefixes: ["+33162*"]
        )

        let rules = withDependencies {
            $0.uuid = .incrementing
            $0.wildcardParser = .live
        } operation: {
            loader.load(manifest, now)
        }
        #expect(rules.count == 1)
        if case .prefix(let prefix) = rules.first?.kind {
            #expect(prefix.fixedDigits == "33162")
            #expect(prefix.wildcardLength == 6)
        } else {
            Issue.record("expected one prefix rule")
        }
    }
}
