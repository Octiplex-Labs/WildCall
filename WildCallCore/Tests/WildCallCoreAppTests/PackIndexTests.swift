import Foundation
import Testing
import CustomDump
@testable import WildCallCoreApp

@Suite struct PackIndexTests {
    @Test func decodesMinimalIndex() throws {
        let json = """
        {
          "version": 1,
          "updatedAt": "2026-05-20T00:00:00Z",
          "packs": [
            {
              "id": "fr.arcep",
              "version": "2026-05-13",
              "country": "FR",
              "kind": "prefixes",
              "url": "https://example.com/fr-arcep.wildcallpack"
            }
          ]
        }
        """.data(using: .utf8)!

        let index = try JSONDecoder().decode(PackIndex.self, from: json)
        #expect(index.version == 1)
        #expect(index.packs.count == 1)
        #expect(index.packs.first?.id == "fr.arcep")
        #expect(index.packs.first?.kind == .prefixes)
        #expect(index.packs.first?.url.absoluteString == "https://example.com/fr-arcep.wildcallpack")
    }

    @Test func decodesEmptyPacksList() throws {
        let json = """
        { "version": 1, "updatedAt": "2026-05-20", "packs": [] }
        """.data(using: .utf8)!
        let index = try JSONDecoder().decode(PackIndex.self, from: json)
        #expect(index.packs.isEmpty)
    }

    @Test func rejectsUnknownKind() {
        let json = """
        {
          "version": 1, "updatedAt": "", "packs": [
            {"id":"x","version":"v1","country":"FR","kind":"unknown_kind","url":"https://x"}
          ]
        }
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(PackIndex.self, from: json)
        }
    }

    @Test func octiplexUrlIsWellFormed() {
        #expect(octiplexPackIndexURL.host() == "raw.githubusercontent.com")
        #expect(octiplexPackIndexURL.path().hasSuffix("/index.json"))
    }
}
