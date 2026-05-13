import Foundation
import SwiftData
import Testing
@testable import WildCallCoreApp

@Suite struct PacksRepositoryTests {
    func makeRepository() -> PacksRepository {
        let container = try! ModelContainer(
            for: PackRecord.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
        return .live(container: container)
    }

    @Test func insertAndFetchRoundtrip() async throws {
        let repo = makeRepository()
        let pack = InstalledPack(
            id: "fr.arcep",
            version: "2026-05-13",
            country: "FR",
            enabled: true,
            installedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await repo.insert(pack)

        let fetched = try await repo.fetch("fr.arcep")
        #expect(fetched == pack)

        let all = try await repo.fetchAll()
        #expect(all == [pack])
    }

    @Test func setEnabledFlipsToggle() async throws {
        let repo = makeRepository()
        try await repo.insert(InstalledPack(
            id: "fr.arcep",
            version: "v1",
            country: "FR",
            enabled: true,
            installedAt: Date(timeIntervalSince1970: 0)
        ))

        try await repo.setEnabled("fr.arcep", false)
        let after = try await repo.fetch("fr.arcep")
        #expect(after?.enabled == false)

        try await repo.setEnabled("fr.arcep", true)
        let afterAgain = try await repo.fetch("fr.arcep")
        #expect(afterAgain?.enabled == true)
    }

    @Test func setEnabledIgnoresUnknownPack() async throws {
        let repo = makeRepository()
        try await repo.setEnabled("nonexistent", false)
        let all = try await repo.fetchAll()
        #expect(all.isEmpty)
    }

    @Test func deleteRemovesPack() async throws {
        let repo = makeRepository()
        try await repo.insert(InstalledPack(
            id: "fr.arcep",
            version: "v1",
            country: "FR",
            enabled: true,
            installedAt: Date(timeIntervalSince1970: 0)
        ))
        try await repo.delete("fr.arcep")
        let after = try await repo.fetch("fr.arcep")
        #expect(after == nil)
    }
}
