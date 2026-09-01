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

    @Test func embeddedFrenchPacksFitUnderTheExtensionCeiling() throws {
        // The bundled packs are what users get by default : every pattern
        // must parse, and each pack must stay under what iOS accepts.
        let packsFolder = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Packs")
        let files = try FileManager.default.contentsOfDirectory(at: packsFolder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".source.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(files.count == 4)

        let parser = WildcardParser.live
        let expander = WildcardExpander.live
        var ids: [String] = []
        for file in files {
            let manifest = try PackManifest.load(from: file)
            ids.append(manifest.id)
            var total = 0
            for pattern in manifest.prefixes {
                let result = withDependencies {
                    $0.wildcardQuotas = WildcardQuotas(perPattern: .max, totalUser: .max, minFixedDigits: 1)
                } operation: {
                    parser.parse(pattern, "FR")
                }
                guard case .success(let prefix) = result else {
                    Issue.record("\(manifest.id): \(pattern) rejected: \(result)")
                    continue
                }
                total += expander.count(prefix)
            }
            #expect(total > 0)
            #expect(total <= WildcardQuotas.measuredExtensionCeiling, "\(manifest.id) has \(total) numbers")
        }
        #expect(ids == ["fr.arcep.1", "fr.arcep.2", "fr.arcep.3", "fr.arcep.4"])

        let first = try PackManifest.load(from: files[0])
        #expect(first.enabledByDefault == true)
        #expect(first.supersedes == ["fr.arcep", "fr.arcep-extra"])
        for file in files.dropFirst() {
            #expect(try PackManifest.load(from: file).enabledByDefault == false)
        }
    }

    @Test func decodesEnabledByDefault() throws {
        let json = """
        {"id":"x","version":"2026-09-02","country":"FR","kind":"prefixes","enabledByDefault":false,"prefixes":["+33162*"]}
        """.data(using: .utf8)!
        #expect(try JSONDecoder().decode(PackManifest.self, from: json).enabledByDefault == false)
    }
}
