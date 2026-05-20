import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Testing
@testable import WildCallCoreApp

@MainActor
@Suite struct PacksFeatureTests {
    let arcep = InstalledPack(
        id: "fr.arcep",
        version: "v1",
        country: "FR",
        enabled: true,
        installedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    @Test func taskLoadsPacks() async {
        let store = TestStore(initialState: PacksFeature.State()) {
            PacksFeature()
        } withDependencies: {
            $0.packsRepository = PacksRepository(
                fetchAll: { [self.arcep] },
                fetch: { _ in nil },
                insert: { _ in },
                setEnabled: { _, _ in },
                delete: { _ in }
            )
            $0.storeOrchestrator = .testValue
        }

        await store.send(.task) { $0.isLoading = true }
        await store.receive(\.packsLoaded) {
            $0.isLoading = false
            $0.packs = [self.arcep]
        }
    }

    @Test func toggleUpdatesStateAndPersistsAndRebuilds() async {
        let setCalls = LockIsolated([(String, Bool)]())
        let rebuildCalls = LockIsolated(0)

        let store = TestStore(
            initialState: PacksFeature.State(packs: [arcep])
        ) {
            PacksFeature()
        } withDependencies: {
            $0.packsRepository = PacksRepository(
                fetchAll: { [] },
                fetch: { _ in nil },
                insert: { _ in },
                setEnabled: { id, enabled in
                    setCalls.withValue { $0.append((id, enabled)) }
                },
                delete: { _ in }
            )
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
        }

        let disabled = InstalledPack(
            id: "fr.arcep", version: "v1", country: "FR",
            enabled: false,
            installedAt: arcep.installedAt
        )
        await store.send(.toggle(id: "fr.arcep", enabled: false)) {
            $0.packs[id: "fr.arcep"] = disabled
            $0.togglingId = "fr.arcep"
        }
        await store.receive(\.toggleCompleted) {
            $0.togglingId = nil
        }
        #expect(setCalls.value.map { $0.0 } == ["fr.arcep"])
        #expect(setCalls.value.map { $0.1 } == [false])
        #expect(rebuildCalls.value == 1)
    }

    @Test func syncButtonTriggersCoordinatorAndStoresSummary() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let summary = SyncSummary(added: ["fr.arcep"], upgraded: [], unchanged: [], failed: [])

        let store = TestStore(initialState: PacksFeature.State()) {
            PacksFeature()
        } withDependencies: {
            $0.packsRepository = PacksRepository(
                fetchAll: { [self.arcep] },
                fetch: { _ in nil },
                insert: { _ in },
                setEnabled: { _, _ in },
                delete: { _ in }
            )
            $0.packSyncCoordinator = PackSyncCoordinator { summary }
            $0.storeOrchestrator = .testValue
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.syncButtonTapped) { $0.isSyncing = true }
        await store.receive(\.syncCompleted) {
            $0.isSyncing = false
            $0.lastSync = now
            $0.lastSyncSummary = summary
        }
        await store.receive(\.task)
        await store.receive(\.packsLoaded)
    }

    @Test func syncFailureStoresError() async {
        let store = TestStore(initialState: PacksFeature.State()) {
            PacksFeature()
        } withDependencies: {
            $0.packsRepository = .testValue
            $0.packSyncCoordinator = PackSyncCoordinator {
                throw SyncError.indexFetchFailed("offline")
            }
            $0.storeOrchestrator = .testValue
            $0.date = .constant(Date())
        }
        store.exhaustivity = .off

        await store.send(.syncButtonTapped) { $0.isSyncing = true }
        await store.receive(\.syncFailed) {
            $0.isSyncing = false
            $0.lastSyncError = EquatableError(SyncError.indexFetchFailed("offline"))
        }
    }
}
