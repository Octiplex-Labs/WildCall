import Dependencies
import Foundation
import SwiftData
import Testing
@testable import WildCallCoreApp

@Suite struct PackBootstrapTests {
    func makeRepositories() -> (RulesRepository, PacksRepository) {
        let container = try! ModelContainer(
            for: BlockRuleRecord.self, PackRecord.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
        return (RulesRepository.live(container: container),
                PacksRepository.live(container: container))
    }

    let manifest = PackManifest(
        id: "fr.arcep",
        version: "2026-05-13",
        country: "FR",
        kind: .prefixes,
        prefixes: ["+33162*", "+33163*"]
    )

    @Test func freshInstallCreatesPackAndRules() async throws {
        let (rulesRepo, packsRepo) = makeRepositories()
        let summary = try await withDependencies {
            $0.rulesRepository = rulesRepo
            $0.packsRepository = packsRepo
            $0.packLoader = .live
            $0.wildcardParser = .live
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .incrementing
        } operation: {
            try await PackBootstrap.live.run([manifest])
        }
        #expect(summary.installed == ["fr.arcep"])
        #expect(summary.upgraded.isEmpty)
        #expect(summary.unchanged.isEmpty)

        let packs = try await packsRepo.fetchAll()
        #expect(packs.count == 1)
        #expect(packs.first?.id == "fr.arcep")
        #expect(packs.first?.enabled == true)

        let rules = try await rulesRepo.fetchAll()
        #expect(rules.count == 2)
        #expect(rules.allSatisfy { $0.source == .pack(packId: "fr.arcep") })
    }

    @Test func sameVersionIsIdempotent() async throws {
        let (rulesRepo, packsRepo) = makeRepositories()
        let deps: @Sendable (inout DependencyValues) -> Void = {
            $0.rulesRepository = rulesRepo
            $0.packsRepository = packsRepo
            $0.packLoader = .live
            $0.wildcardParser = .live
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .incrementing
        }
        let firstSummary = try await withDependencies(deps) { try await PackBootstrap.live.run([manifest]) }
        #expect(firstSummary.installed == ["fr.arcep"])

        let secondSummary = try await withDependencies(deps) { try await PackBootstrap.live.run([manifest]) }
        #expect(secondSummary.unchanged == ["fr.arcep"])
        #expect(secondSummary.installed.isEmpty)
        #expect(secondSummary.upgraded.isEmpty)

        // No duplicated rules.
        let rules = try await rulesRepo.fetchAll()
        #expect(rules.count == 2)
    }

    @Test func newVersionReplacesOldPackRules() async throws {
        let (rulesRepo, packsRepo) = makeRepositories()
        let v1 = manifest
        let v2 = PackManifest(
            id: "fr.arcep",
            version: "2026-06-01",  // bumped
            country: "FR",
            kind: .prefixes,
            prefixes: ["+33162*", "+33163*", "+33164*"]  // one more
        )

        let deps: @Sendable (inout DependencyValues) -> Void = {
            $0.rulesRepository = rulesRepo
            $0.packsRepository = packsRepo
            $0.packLoader = .live
            $0.wildcardParser = .live
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .incrementing
        }

        _ = try await withDependencies(deps) { try await PackBootstrap.live.run([v1]) }
        let summary = try await withDependencies(deps) { try await PackBootstrap.live.run([v2]) }
        #expect(summary.upgraded == ["fr.arcep"])

        let rules = try await rulesRepo.fetchAll()
        #expect(rules.count == 3)  // three prefixes, no duplicates from v1
        let pack = try await packsRepo.fetch("fr.arcep")
        #expect(pack?.version == "2026-06-01")
    }

    @Test func olderEmbeddedVersionDoesNotDowngradeSyncedPack() async throws {
        // A remote sync may be ahead of the bundle : bootstrap must not
        // ping-pong the pack back to the embedded version at each launch.
        let (rulesRepo, packsRepo) = makeRepositories()
        let deps: @Sendable (inout DependencyValues) -> Void = {
            $0.rulesRepository = rulesRepo
            $0.packsRepository = packsRepo
            $0.packLoader = .live
            $0.wildcardParser = .live
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .incrementing
        }
        let synced = PackManifest(id: "fr.arcep", version: "2026-12-01", country: "FR", kind: .prefixes, prefixes: ["+33162*", "+33163*", "+33164*"])
        _ = try await withDependencies(deps) { try await PackBootstrap.live.run([synced]) }

        let summary = try await withDependencies(deps) { try await PackBootstrap.live.run([manifest]) }
        #expect(summary.unchanged == ["fr.arcep"])
        #expect(summary.upgraded.isEmpty)
        #expect(try await packsRepo.fetch("fr.arcep")?.version == "2026-12-01")
        #expect(try await rulesRepo.fetchAll().count == 3)
    }

    @Test func upgradePreservesUserDisabledFlag() async throws {
        let (rulesRepo, packsRepo) = makeRepositories()
        let deps: @Sendable (inout DependencyValues) -> Void = {
            $0.rulesRepository = rulesRepo
            $0.packsRepository = packsRepo
            $0.packLoader = .live
            $0.wildcardParser = .live
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .incrementing
        }
        _ = try await withDependencies(deps) { try await PackBootstrap.live.run([manifest]) }
        try await packsRepo.setEnabled("fr.arcep", false)

        let v2 = PackManifest(id: "fr.arcep", version: "2026-06-01", country: "FR", kind: .prefixes, prefixes: ["+33162*"])
        _ = try await withDependencies(deps) { try await PackBootstrap.live.run([v2]) }
        #expect(try await packsRepo.fetch("fr.arcep")?.enabled == false)
    }

    @Test func supersededPackIsRemovedWithItsRules() async throws {
        let (rulesRepo, packsRepo) = makeRepositories()
        let deps: @Sendable (inout DependencyValues) -> Void = {
            $0.rulesRepository = rulesRepo
            $0.packsRepository = packsRepo
            $0.packLoader = .live
            $0.wildcardParser = .live
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .incrementing
        }
        let extra = PackManifest(id: "fr.arcep-extra", version: "2026-05-21", country: "FR", kind: .prefixes, prefixes: ["+33270*"])
        _ = try await withDependencies(deps) { try await PackBootstrap.live.run([extra]) }
        #expect(try await rulesRepo.fetchAll().count == 1)

        let merged = PackManifest(
            id: "fr.arcep", version: "2026-09-01", country: "FR", kind: .prefixes,
            supersedes: ["fr.arcep-extra"], prefixes: ["+33162*", "+33270*"]
        )
        let summary = try await withDependencies(deps) { try await PackBootstrap.live.run([merged]) }
        #expect(summary.removed == ["fr.arcep-extra"])
        #expect(summary.installed == ["fr.arcep"])
        #expect(summary.didChangeAnything)

        let packs = try await packsRepo.fetchAll()
        #expect(packs.map(\.id) == ["fr.arcep"])
        let rules = try await rulesRepo.fetchAll()
        #expect(rules.count == 2)
        #expect(rules.allSatisfy { $0.source == .pack(packId: "fr.arcep") })
    }

    @Test func versionComparisonIsChronologicalForIsoDates() {
        #expect(PackBootstrap.isNewer("2026-09-01", than: "2026-05-13"))
        #expect(!PackBootstrap.isNewer("2026-05-13", than: "2026-09-01"))
        #expect(!PackBootstrap.isNewer("2026-09-01", than: "2026-09-01"))
        #expect(PackBootstrap.isNewer("v10", than: "v9"))
    }
}
