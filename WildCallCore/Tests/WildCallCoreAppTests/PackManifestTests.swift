import Dependencies
import Foundation
import Testing
import CustomDump
@testable import WildCallCoreApp

@Suite struct PackManifestTests {
    @Test func decodesMinimalManifest() throws {
        let json = """
        {
          "id": "fr.arcep",
          "version": "2026-05-13",
          "country": "FR",
          "kind": "prefixes",
          "prefixes": ["+33162*", "+33163*"]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(PackManifest.self, from: json)
        #expect(manifest.id == "fr.arcep")
        #expect(manifest.version == "2026-05-13")
        #expect(manifest.country == "FR")
        #expect(manifest.kind == .prefixes)
        #expect(manifest.prefixes == ["+33162*", "+33163*"])
        #expect(manifest.title == nil)
    }

    @Test func decodesManifestWithPublisherKey() throws {
        let json = """
        {
          "id": "fr.thirdparty",
          "version": "v1",
          "country": "FR",
          "kind": "prefixes",
          "publisherKey": "cb7974ed754089790a97afb61d3aa8d7a68373d89a5313615a358f453f993ae4",
          "prefixes": []
        }
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(PackManifest.self, from: json)
        #expect(manifest.publisherKey != nil)
        let bytes = manifest.publisherKeyBytes()
        #expect(bytes?.count == 32)
        #expect(bytes?.first == 0xcb)
    }

    @Test func rejectsMalformedPublisherKeyHex() throws {
        let json = """
        {
          "id": "x", "version": "v1", "country": "FR", "kind": "prefixes",
          "publisherKey": "notvalidhex",
          "prefixes": []
        }
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(PackManifest.self, from: json)
        #expect(manifest.publisherKey == "notvalidhex")
        #expect(manifest.publisherKeyBytes() == nil)  // helper guards length & validity
    }

    @Test func rejectsShortPublisherKey() throws {
        let json = """
        {
          "id": "x", "version": "v1", "country": "FR", "kind": "prefixes",
          "publisherKey": "abcd",
          "prefixes": []
        }
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(PackManifest.self, from: json)
        #expect(manifest.publisherKeyBytes() == nil)
    }

    @Test func peekManifestReadsArchiveWithoutVerifying() throws {
        let archive = PackArchive()
        let manifestJSON = Data("{\"id\":\"x\",\"version\":\"v1\",\"country\":\"FR\",\"kind\":\"prefixes\",\"prefixes\":[]}".utf8)
        let bytes = try archive.write(.init(
            manifest: manifestJSON,
            signature: Data(repeating: 0, count: 64),  // garbage signature
            payload: nil
        ))
        // peekManifest should still decode (no signature check)
        let manifest = try archive.peekManifest(bytes)
        #expect(manifest.id == "x")
    }

    @Test func decodesRichManifest() throws {
        let json = """
        {
          "id": "fr.arcep",
          "version": "2026-05-13",
          "country": "FR",
          "kind": "prefixes",
          "title": "Démarchage FR",
          "license": "public domain",
          "notes": "subset",
          "prefixes": ["+33162*"]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(PackManifest.self, from: json)
        #expect(manifest.title == "Démarchage FR")
        #expect(manifest.license == "public domain")
        #expect(manifest.notes == "subset")
    }

    @Test func loadsEmbeddedArcepManifestFromBundle() throws {
        // The embedded ARCEP pack must always parse : it ships with the .app.
        let url = Bundle.main.url(forResource: "prefixes-FR.source", withExtension: "json")
        // In test runners the resource may live under a different bundle; skip if not present.
        guard let url else { return }
        let manifest = try PackManifest.load(from: url)
        #expect(manifest.id == "fr.arcep")
        #expect(manifest.kind == .prefixes)
        #expect(manifest.prefixes.count == 6)
    }

    @Test func reportsMissingFile() {
        let url = URL(filePath: "/nonexistent/pack.json")
        #expect(throws: PackManifest.LoadError.fileMissing(url)) {
            _ = try PackManifest.load(from: url)
        }
    }

    @Test func reportsDecodingFailure() throws {
        let tmp = URL(filePath: NSTemporaryDirectory())
            .appendingPathComponent("PackManifestTest-\(UUID().uuidString).json")
        try "not json".data(using: .utf8)!.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        do {
            _ = try PackManifest.load(from: tmp)
            Issue.record("expected decoding failure")
        } catch PackManifest.LoadError.decodingFailed {
            // expected
        } catch {
            Issue.record("expected .decodingFailed, got \(error)")
        }
    }

    @Test func decodesSupersedes() throws {
        let json = """
        {"id":"fr.arcep","version":"2026-09-01","country":"FR","kind":"prefixes","supersedes":["fr.arcep-extra"],"prefixes":["+33162*"]}
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(PackManifest.self, from: json)
        #expect(manifest.supersedes == ["fr.arcep-extra"])
    }

    @Test func embeddedFrenchPackFitsTheShippedExtensions() throws {
        // The bundled pack is what users get by default : every pattern
        // must parse and the total must fit in the extensions we ship.
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Packs/prefixes-FR.source.json")
        let manifest = try PackManifest.load(from: url)
        #expect(manifest.id == "fr.arcep")
        #expect(manifest.enabledByDefault == true)
        #expect(manifest.supersedes == ["fr.arcep.1", "fr.arcep.2", "fr.arcep.3", "fr.arcep.4", "fr.arcep-extra"])
        #expect(manifest.title?.isEmpty == false)

        let parser = WildcardParser.live
        let expander = WildcardExpander.live
        var total = 0
        for pattern in manifest.prefixes {
            let result = withDependencies {
                $0.wildcardQuotas = WildcardQuotas(perPattern: .max, totalUser: .max, minFixedDigits: 1)
            } operation: {
                parser.parse(pattern, "FR")
            }
            guard case .success(let prefix) = result else {
                Issue.record("\(pattern) rejected: \(result)")
                continue
            }
            #expect(prefix.fixedDigits.hasPrefix("33"))
            total += expander.count(prefix)
        }
        #expect(total > 5_000_000)
        #expect(total <= WildcardQuotas.default.totalCapacity, "\(total) numbers exceed the shipped extensions")
    }

    @Test func embeddedOverseasPackCoversEachTerritoryInBothForms() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Packs/prefixes-FR-DOM.source.json")
        let manifest = try PackManifest.load(from: url)
        #expect(manifest.id == "fr.arcep.dom")
        #expect(manifest.enabledByDefault == true)
        #expect(manifest.title?.isEmpty == false)

        let parser = WildcardParser.live
        let expander = WildcardExpander.live
        var totals: [String: Int] = [:]
        for pattern in manifest.prefixes {
            let result = withDependencies {
                $0.wildcardQuotas = WildcardQuotas(perPattern: .max, totalUser: .max, minFixedDigits: 1)
            } operation: {
                parser.parse(pattern, "FR")
            }
            guard case .success(let prefix) = result else {
                Issue.record("\(pattern) rejected: \(result)")
                continue
            }
            let code = String(prefix.fixedDigits.prefix(prefix.fixedDigits.hasPrefix("33") ? 2 : 3))
            #expect(String(prefix.fixedDigits.dropFirst(code.count)).hasPrefix("947"))
            totals[code, default: 0] += expander.count(prefix)
        }
        // Every block appears once under its territory code and once under +33.
        #expect(Set(totals.keys) == ["33", "262", "590", "594", "596"])
        #expect(totals["33"] == totals.filter { $0.key != "33" }.values.reduce(0, +))
    }

    @Test func embeddedUSPackIdentifiesExactNumbers() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Packs/prefixes-US.source.json")
        let manifest = try PackManifest.load(from: url)
        #expect(manifest.id == "us.complaints")
        #expect(manifest.action == .identify)
        #expect(manifest.label == "Spam signalé")
        #expect(!manifest.prefixes.isEmpty)

        let parser = WildcardParser.live
        for pattern in manifest.prefixes {
            let result = withDependencies {
                $0.wildcardQuotas = WildcardQuotas(perPattern: .max, totalUser: .max, minFixedDigits: 1)
            } operation: {
                parser.parse(pattern, "US")
            }
            guard case .success(let prefix) = result else {
                Issue.record("\(pattern) rejected: \(result)")
                continue
            }
            #expect(prefix.fixedDigits.hasPrefix("1"))
            #expect(prefix.wildcardLength == 0, "\(pattern) must name a single number")
        }
    }

    @Test func embeddedGermanPackListsExactNumbers() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Packs/prefixes-DE.source.json")
        let manifest = try PackManifest.load(from: url)
        #expect(manifest.id == "de.bnetza")
        #expect(manifest.action == .identify)
        #expect(manifest.label == "Spam signalé")
        #expect(manifest.prefixes.count > 1_000)
        // Variable-length national numbers: a `*` would pad each one to the
        // longest German length and flag thousands of innocent numbers.
        #expect(manifest.prefixes.allSatisfy { !$0.contains("*") })
        #expect(manifest.prefixes.allSatisfy { PackLoader.exactNumber($0) != nil })
    }

    @Test func embeddedPeruPackCoversTheWhole500Series() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Packs/prefixes-PE.source.json")
        let manifest = try PackManifest.load(from: url)
        #expect(manifest.id == "pe.mtc")
        #expect(manifest.enabledByDefault == false)
        #expect(manifest.prefixes == ["+51500*"])

        let result = withDependencies {
            $0.wildcardQuotas = WildcardQuotas(perPattern: .max, totalUser: .max, minFixedDigits: 1)
        } operation: {
            WildcardParser.live.parse("+51500*", "PE")
        }
        guard case .success(let prefix) = result else {
            Issue.record("+51500* rejected: \(result)")
            return
        }
        // Peruvian numbers are 9 digits: 500 + 6 free digits.
        #expect(WildcardExpander.live.count(prefix) == 1_000_000)
    }

    @Test func decodesActionAndLabel() throws {
        let json = """
        {"id":"x","version":"2026-10-18","country":"US","kind":"prefixes","action":"identify","label":"Spam signalé","prefixes":["+12025550143*"]}
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(PackManifest.self, from: json)
        #expect(manifest.action == .identify)
        #expect(manifest.label == "Spam signalé")
    }

    @Test func decodesEnabledByDefault() throws {
        let json = """
        {"id":"x","version":"2026-09-02","country":"FR","kind":"prefixes","enabledByDefault":false,"prefixes":["+33162*"]}
        """.data(using: .utf8)!
        #expect(try JSONDecoder().decode(PackManifest.self, from: json).enabledByDefault == false)
    }
}
