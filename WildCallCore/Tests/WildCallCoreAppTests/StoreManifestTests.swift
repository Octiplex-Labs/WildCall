import Foundation
import Testing
import CustomDump
@testable import WildCallCoreApp

@Suite struct StoreManifestTests {
    @Test func codableRoundtrip() throws {
        let manifest = StoreManifest(
            buildDate: Date(timeIntervalSince1970: 1_700_000_000),
            block: .init(count: 20_000_000, ranges: 20, bytes: 344, sha256: "abc"),
            ident: .init(count: 12, ranges: 12, bytes: 240, sha256: "def"),
            sources: ["user", "pack:fr.arcep"],
            lastReload: .init(date: Date(timeIntervalSince1970: 1_700_000_090), succeeded: false, failure: .extensionDisabled)
        )
        let url = makeTempURL().deletingPathExtension().appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        try manifest.write(to: url)
        let loaded = try StoreManifest.load(from: url)
        expectNoDifference(loaded, manifest)
        #expect(loaded?.formatVersion == StoreManifest.currentFormatVersion)
        #expect(loaded?.totalNumbers == 20_000_012)
    }

    @Test func legacyManifestWithoutVersionDecodesAsVersionOne() throws {
        let json = """
        {"buildDate":"2026-05-01T00:00:00Z","block":{"count":3,"bytes":40,"sha256":"a"},"ident":{"count":0,"bytes":24,"sha256":"b"},"sources":["user"]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(StoreManifest.self, from: Data(json.utf8))
        #expect(manifest.formatVersion == 1)
        #expect(manifest.block.ranges == 3)
        #expect(manifest.lastReload == nil)
    }

    @Test func loadReturnsNilForMissingFile() throws {
        let url = makeTempURL().deletingPathExtension().appendingPathExtension("json")
        let loaded = try StoreManifest.load(from: url)
        #expect(loaded == nil)
    }
}
