import ComposableArchitecture
import CryptoKit
import Dependencies
import Foundation
import SwiftData
import Testing
@testable import WildCallCoreApp

@MainActor
@Suite struct PackImportFeatureTests {
    func makeRepositories() -> (RulesRepository, PacksRepository) {
        let container = try! ModelContainer(
            for: BlockRuleRecord.self, PackRecord.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
        return (RulesRepository.live(container: container),
                PacksRepository.live(container: container))
    }

    /// Build a signed archive on disk and return its URL. Caller is responsible
    /// for deletion (we use a temp dir so this is mostly cosmetic).
    func writeFixture(
        id: String = "fr.arcep",
        version: String = "v1",
        signerKey: Curve25519.Signing.PrivateKey
    ) throws -> URL {
        let manifest = """
        {"id":"\(id)","version":"\(version)","country":"FR","kind":"prefixes","prefixes":["+33162*"]}
        """
        let manifestData = Data(manifest.utf8)
        let signature = try signerKey.signature(for: manifestData)
        let archive = try PackArchive().write(.init(
            manifest: manifestData,
            signature: signature,
            payload: nil
        ))
        let url = URL(filePath: NSTemporaryDirectory())
            .appendingPathComponent("import-test-\(UUID().uuidString).wildcallpack")
        try archive.write(to: url)
        return url
    }

    @Test func happyPathReachesAwaitingConfirmation() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let url = try writeFixture(signerKey: key)
        defer { try? FileManager.default.removeItem(at: url) }

        let (rulesRepo, packsRepo) = makeRepositories()

        let store = TestStore(initialState: PackImportFeature.State(fileURL: url)) {
            PackImportFeature()
        } withDependencies: {
            $0.packLoader = PackLoader(
                load: { _, _ in [] },
                loadFromArchive: { data, _, now in
                    PackLoader.live.loadFromArchive(data, key.publicKey.rawRepresentation, now)
                }
            )
            $0.rulesRepository = rulesRepo
            $0.packsRepository = packsRepo
            $0.storeOrchestrator = .testValue
            $0.wildcardParser = .live
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.loadResult.success)
        if case .awaitingConfirmation(let loaded) = store.state.phase {
            #expect(loaded.manifest.id == "fr.arcep")
            #expect(loaded.rules.count == 1)
        } else {
            Issue.record("expected awaitingConfirmation, got \(store.state.phase)")
        }
    }

    // The full confirm → install → rebuild flow is covered indirectly by
    // PackBootstrapTests (same install code path) and StoreOrchestratorTests
    // (rebuild). A direct test here triggers a Swift 6 IR generation crash
    // in the specific combination of LockIsolated + closure-captured state +
    // @MainActor @Suite + nested await flows. Revisit when the toolchain
    // catches up.

    @Test func cancelTappedFinishes() async {
        let store = TestStore(
            initialState: PackImportFeature.State(
                fileURL: URL(filePath: "/tmp/x.wildcallpack"),
                phase: .reading
            )
        ) {
            PackImportFeature()
        } withDependencies: {
            $0.packLoader = .testValue
            $0.rulesRepository = .testValue
            $0.packsRepository = .testValue
            $0.storeOrchestrator = .testValue
        }

        await store.send(.cancelTapped)
        await store.receive(\.delegate.finished)
    }

    @Test func badSignatureSurfacesAsFailed() async throws {
        let signerKey = Curve25519.Signing.PrivateKey()
        let url = try writeFixture(signerKey: signerKey)
        defer { try? FileManager.default.removeItem(at: url) }
        // Verify with a DIFFERENT key : should fail.
        let otherKey = Curve25519.Signing.PrivateKey()

        let store = TestStore(initialState: PackImportFeature.State(fileURL: url)) {
            PackImportFeature()
        } withDependencies: {
            $0.packLoader = PackLoader(
                load: { _, _ in [] },
                loadFromArchive: { data, _, now in
                    PackLoader.live.loadFromArchive(data, otherKey.publicKey.rawRepresentation, now)
                }
            )
            $0.rulesRepository = .testValue
            $0.packsRepository = .testValue
            $0.storeOrchestrator = .testValue
            $0.wildcardParser = .live
            $0.date = .constant(Date())
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.loadResult.failure)
        if case .failed = store.state.phase {
            // expected
        } else {
            Issue.record("expected .failed, got \(store.state.phase)")
        }
    }
}
