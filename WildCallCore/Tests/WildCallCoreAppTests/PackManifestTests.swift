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
        // The embedded ARCEP pack must always parse — it ships with the .app.
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
}
