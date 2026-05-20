import CryptoKit
import Dependencies
import Foundation
import SwiftData
import Testing
@testable import WildCallCoreApp

@Suite struct PackSyncCoordinatorTests {
    func makeRepositories() -> (RulesRepository, PacksRepository) {
        let container = try! ModelContainer(
            for: BlockRuleRecord.self, PackRecord.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
        return (RulesRepository.live(container: container),
                PacksRepository.live(container: container))
    }

    /// Build a valid signed .wildcallpack archive in memory, simulating what
    /// the publisher tool would produce.
    func makeSignedArchive(
        id: String = "fr.arcep",
        version: String = "v1",
        prefixes: [String] = ["+33162*"],
        key: Curve25519.Signing.PrivateKey
    ) throws -> Data {
        let manifest = """
        {
          "id": "\(id)",
          "version": "\(version)",
          "country": "FR",
          "kind": "prefixes",
          "prefixes": \(prefixes.map { "\"\($0)\"" }.joined(separator: ", ").prepending("[").appending("]"))
        }
        """
        let manifestData = Data(manifest.utf8)
        let signature = try key.signature(for: manifestData)
        return try PackArchive().write(.init(
            manifest: manifestData,
            signature: signature,
            payload: nil
        ))
    }

    /// Reusable dependency overrides for sync tests. We override OctiplexTrust
    /// indirectly by injecting a test key as the signer and ensuring the
    /// coordinator uses OctiplexTrust.publicKey to verify — which means the
    /// test must sign with the *real* embedded Octiplex private key. Since we
    /// don't have that private key in tests, we override the loader instead
    /// to short-circuit verification with our test public key.
    func testKey() -> Curve25519.Signing.PrivateKey { Curve25519.Signing.PrivateKey() }

    @Test func syncInstallsNewPackAndTriggersRebuild() async throws {
        let key = testKey()
        let archive = try makeSignedArchive(id: "fr.arcep", version: "v1", key: key)
        let entry = PackIndexEntry(
            id: "fr.arcep", version: "v1", country: "FR", kind: .prefixes,
            url: URL(string: "https://example.com/fr.arcep.v1.wildcallpack")!
        )
        let index = PackIndex(version: 1, updatedAt: "2026-05-20", packs: [entry])

        let (rulesRepo, packsRepo) = makeRepositories()
        let rebuildCalls = LockIsolated(0)

        let summary = try await withDependencies {
            $0.packIndexFetcher = PackIndexFetcher { index }
            $0.packFetcher = PackFetcher { _ in archive }
            $0.packLoader = PackLoader(
                load: { _, _ in [] },
                loadFromArchive: { data, _, now in
                    // Verify with the test key (bypass OctiplexTrust)
                    PackLoader.live.loadFromArchive(data, key.publicKey.rawRepresentation, now)
                }
            )
            $0.rulesRepository = rulesRepo
            $0.packsRepository = packsRepo
            $0.storeOrchestrator = StoreOrchestrator(
                rebuildAndReload: {
                    rebuildCalls.withValue { $0 += 1 }
                    return RebuildSummary(
                        blockCount: 0, identCount: 0,
                        block: .init(count: 0, bytesWritten: 0, sha256: ""),
                        ident: .init(count: 0, bytesWritten: 0, sha256: "")
                    )
                }
            )
            $0.wildcardParser = .live
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .incrementing
        } operation: {
            try await PackSyncCoordinator.live.sync()
        }

        #expect(summary.added == ["fr.arcep"])
        #expect(summary.upgraded.isEmpty)
        #expect(summary.unchanged.isEmpty)
        #expect(summary.failed.isEmpty)
        #expect(rebuildCalls.value == 1)

        let installed = try await packsRepo.fetch("fr.arcep")
        #expect(installed?.version == "v1")
        #expect(installed?.enabled == true)
    }

    @Test func sameVersionIsUnchanged() async throws {
        let key = testKey()
        let archive = try makeSignedArchive(id: "fr.arcep", version: "v1", key: key)
        let entry = PackIndexEntry(
            id: "fr.arcep", version: "v1", country: "FR", kind: .prefixes,
            url: URL(string: "https://example.com/fr.arcep.v1.wildcallpack")!
        )
        let index = PackIndex(version: 1, updatedAt: "", packs: [entry])

        let (rulesRepo, packsRepo) = makeRepositories()
        try await packsRepo.insert(InstalledPack(
            id: "fr.arcep", version: "v1", country: "FR", enabled: true,
            installedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let rebuildCalls = LockIsolated(0)

        let summary = try await withDependencies {
            $0.packIndexFetcher = PackIndexFetcher { index }
            $0.packFetcher = PackFetcher { _ in archive }
            $0.packLoader = PackLoader(
                load: { _, _ in [] },
                loadFromArchive: { data, _, now in
                    PackLoader.live.loadFromArchive(data, key.publicKey.rawRepresentation, now)
                }
            )
            $0.rulesRepository = rulesRepo
            $0.packsRepository = packsRepo
            $0.storeOrchestrator = StoreOrchestrator(
                rebuildAndReload: {
                    rebuildCalls.withValue { $0 += 1 }
                    return RebuildSummary(
                        blockCount: 0, identCount: 0,
                        block: .init(count: 0, bytesWritten: 0, sha256: ""),
                        ident: .init(count: 0, bytesWritten: 0, sha256: "")
                    )
                }
            )
            $0.wildcardParser = .live
            $0.date = .constant(Date())
            $0.uuid = .incrementing
        } operation: {
            try await PackSyncCoordinator.live.sync()
        }

        #expect(summary.unchanged == ["fr.arcep"])
        #expect(summary.added.isEmpty)
        #expect(rebuildCalls.value == 0)  // no change → no rebuild
    }

    @Test func versionBumpUpgradesPreservingEnabledFlag() async throws {
        let key = testKey()
        let archiveV2 = try makeSignedArchive(id: "fr.arcep", version: "v2", key: key)
        let entry = PackIndexEntry(
            id: "fr.arcep", version: "v2", country: "FR", kind: .prefixes,
            url: URL(string: "https://example.com/fr.arcep.v2.wildcallpack")!
        )
        let index = PackIndex(version: 1, updatedAt: "", packs: [entry])

        let (rulesRepo, packsRepo) = makeRepositories()
        // Pre-installed v1 with user-disabled state
        try await packsRepo.insert(InstalledPack(
            id: "fr.arcep", version: "v1", country: "FR", enabled: false,
            installedAt: Date(timeIntervalSince1970: 0)
        ))

        let summary = try await withDependencies {
            $0.packIndexFetcher = PackIndexFetcher { index }
            $0.packFetcher = PackFetcher { _ in archiveV2 }
            $0.packLoader = PackLoader(
                load: { _, _ in [] },
                loadFromArchive: { data, _, now in
                    PackLoader.live.loadFromArchive(data, key.publicKey.rawRepresentation, now)
                }
            )
            $0.rulesRepository = rulesRepo
            $0.packsRepository = packsRepo
            $0.storeOrchestrator = StoreOrchestrator(
                rebuildAndReload: {
                    RebuildSummary(
                        blockCount: 0, identCount: 0,
                        block: .init(count: 0, bytesWritten: 0, sha256: ""),
                        ident: .init(count: 0, bytesWritten: 0, sha256: "")
                    )
                }
            )
            $0.wildcardParser = .live
            $0.date = .constant(Date(timeIntervalSince1970: 1_800_000_000))
            $0.uuid = .incrementing
        } operation: {
            try await PackSyncCoordinator.live.sync()
        }

        #expect(summary.upgraded == ["fr.arcep"])
        let installed = try await packsRepo.fetch("fr.arcep")
        #expect(installed?.version == "v2")
        #expect(installed?.enabled == false)  // user's choice preserved
    }

    @Test func indexFetchFailureThrows() async {
        await #expect(throws: SyncError.self) {
            try await withDependencies {
                $0.packIndexFetcher = PackIndexFetcher {
                    throw URLError(.notConnectedToInternet)
                }
                $0.packFetcher = .testValue
                $0.packLoader = .testValue
                $0.rulesRepository = .testValue
                $0.packsRepository = .testValue
                $0.storeOrchestrator = .testValue
            } operation: {
                _ = try await PackSyncCoordinator.live.sync()
            }
        }
    }

    @Test func failedPackDoesNotAbortOtherPacks() async throws {
        let key = testKey()
        let goodArchive = try makeSignedArchive(id: "fr.arcep", version: "v1", key: key)
        let entries = [
            PackIndexEntry(id: "fr.broken", version: "v1", country: "FR", kind: .prefixes,
                           url: URL(string: "https://example.com/broken.wildcallpack")!),
            PackIndexEntry(id: "fr.arcep", version: "v1", country: "FR", kind: .prefixes,
                           url: URL(string: "https://example.com/arcep.wildcallpack")!),
        ]
        let index = PackIndex(version: 1, updatedAt: "", packs: entries)

        let (rulesRepo, packsRepo) = makeRepositories()
        let summary = try await withDependencies {
            $0.packIndexFetcher = PackIndexFetcher { index }
            $0.packFetcher = PackFetcher { url in
                if url.absoluteString.contains("broken") {
                    throw URLError(.timedOut)
                }
                return goodArchive
            }
            $0.packLoader = PackLoader(
                load: { _, _ in [] },
                loadFromArchive: { data, _, now in
                    PackLoader.live.loadFromArchive(data, key.publicKey.rawRepresentation, now)
                }
            )
            $0.rulesRepository = rulesRepo
            $0.packsRepository = packsRepo
            $0.storeOrchestrator = StoreOrchestrator(
                rebuildAndReload: {
                    RebuildSummary(
                        blockCount: 0, identCount: 0,
                        block: .init(count: 0, bytesWritten: 0, sha256: ""),
                        ident: .init(count: 0, bytesWritten: 0, sha256: "")
                    )
                }
            )
            $0.wildcardParser = .live
            $0.date = .constant(Date())
            $0.uuid = .incrementing
        } operation: {
            try await PackSyncCoordinator.live.sync()
        }

        #expect(summary.added == ["fr.arcep"])
        #expect(summary.failed.count == 1)
        #expect(summary.failed.first?.packId == "fr.broken")
    }
}

private extension String {
    func prepending(_ prefix: String) -> String { prefix + self }
}
