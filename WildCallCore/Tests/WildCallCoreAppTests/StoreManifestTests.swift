import Foundation
import Testing
import CustomDump
import WildCallCoreShared
@testable import WildCallCoreApp

@Suite struct StoreManifestTests {
    @Test func codableRoundtrip() throws {
        let manifest = StoreManifest(
            buildDate: Date(timeIntervalSince1970: 1_700_000_000),
            block: .init(count: 20_000_000, ranges: 20, bytes: 344, sha256: "abc"),
            ident: .init(count: 12, ranges: 12, bytes: 240, sha256: "def"),
            slots: ExtensionSlot.all.map { .init(slot: $0.index, block: .init(count: 5_000_003, ranges: 5, bytes: 100, sha256: "s"), ident: .init(count: 3, ranges: 3, bytes: 80, sha256: "t")) },
            sources: ["user", "pack:fr.arcep"],
            lastReload: .init(date: Date(timeIntervalSince1970: 1_700_000_090), succeeded: false, failure: .extensionDisabled, slot: 3)
        )
        let url = makeTempURL().deletingPathExtension().appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        try manifest.write(to: url)
        let loaded = try StoreManifest.load(from: url)
        expectNoDifference(loaded, manifest)
        #expect(loaded?.formatVersion == StoreManifest.currentFormatVersion)
        #expect(loaded?.totalNumbers == 20_000_012)
        #expect(loaded?.matchesSlotLayout == true)
        #expect(loaded?.lastReload?.slot == 3)
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
        #expect(manifest.slots.isEmpty)
        #expect(manifest.matchesSlotLayout == false)
    }

    @Test func loadReturnsNilForMissingFile() throws {
        let url = makeTempURL().deletingPathExtension().appendingPathExtension("json")
        let loaded = try StoreManifest.load(from: url)
        #expect(loaded == nil)
    }
}
