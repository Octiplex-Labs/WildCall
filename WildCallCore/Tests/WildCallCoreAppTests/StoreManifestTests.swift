import Foundation
import Testing
import CustomDump
@testable import WildCallCoreApp

@Suite struct StoreManifestTests {
    @Test func codableRoundtrip() throws {
        let manifest = StoreManifest(
            buildDate: Date(timeIntervalSince1970: 1_700_000_000),
            block: .init(count: 1_234, bytes: 9_888, sha256: "abc"),
            ident: .init(count: 12, bytes: 240, sha256: "def"),
            sources: ["user", "pack:fr.arcep"]
        )
        let url = makeTempURL().deletingPathExtension().appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        try manifest.write(to: url)
        let loaded = try StoreManifest.load(from: url)
        expectNoDifference(loaded, manifest)
    }

    @Test func loadReturnsNilForMissingFile() throws {
        let url = makeTempURL().deletingPathExtension().appendingPathExtension("json")
        let loaded = try StoreManifest.load(from: url)
        #expect(loaded == nil)
    }
}
