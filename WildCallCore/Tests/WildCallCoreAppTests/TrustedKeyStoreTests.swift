import Foundation
import SwiftData
import Testing
@testable import WildCallCoreApp

@Suite struct TrustedKeyStoreTests {
    func makeStore() -> TrustedKeyStore {
        let container = try! ModelContainer(
            for: TrustedKeyRecord.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
        return .live(container: container)
    }

    let sample = TrustedKey(
        packId: "fr.thirdparty.example",
        publicKey: Data(repeating: 0xAB, count: 32),
        fingerprint: "AA:BB:CC:DD:EE:FF:11:22",
        pinnedAt: Date(timeIntervalSince1970: 1_700_000_000),
        sourceURL: "https://example.com/pack.wildcallpack"
    )

    @Test func pinAndFetchRoundtrip() async throws {
        let store = makeStore()
        try await store.pin(sample)
        let fetched = try await store.fetch(sample.packId)
        #expect(fetched == sample)
    }

    @Test func pinOverwritesExisting() async throws {
        let store = makeStore()
        try await store.pin(sample)

        let updated = TrustedKey(
            packId: sample.packId,
            publicKey: Data(repeating: 0xCD, count: 32),
            fingerprint: "11:22:33:44:55:66:77:88",
            pinnedAt: Date(timeIntervalSince1970: 1_800_000_000),
            sourceURL: sample.sourceURL
        )
        try await store.pin(updated)

        let fetched = try await store.fetch(sample.packId)
        #expect(fetched == updated)
        let all = try await store.fetchAll()
        #expect(all.count == 1)  // no duplicate
    }

    @Test func unpinRemoves() async throws {
        let store = makeStore()
        try await store.pin(sample)
        try await store.unpin(sample.packId)
        let fetched = try await store.fetch(sample.packId)
        #expect(fetched == nil)
    }

    @Test func fetchUnknownReturnsNil() async throws {
        let store = makeStore()
        let fetched = try await store.fetch("nonexistent")
        #expect(fetched == nil)
    }

    @Test func fetchAllOrdersByPinnedAt() async throws {
        let store = makeStore()
        let older = TrustedKey(
            packId: "older",
            publicKey: Data(repeating: 1, count: 32),
            fingerprint: "X",
            pinnedAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let newer = TrustedKey(
            packId: "newer",
            publicKey: Data(repeating: 2, count: 32),
            fingerprint: "Y",
            pinnedAt: Date(timeIntervalSince1970: 2_000_000)
        )
        try await store.pin(newer)
        try await store.pin(older)
        let all = try await store.fetchAll()
        #expect(all.map(\.packId) == ["older", "newer"])
    }
}
