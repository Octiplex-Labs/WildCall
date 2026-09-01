import Foundation
import Testing
import ComposableArchitecture
import WildCallCoreShared
@testable import WildCallCoreApp

@MainActor
@Suite struct AppFeatureTests {
    func makeContainer() throws -> SharedContainer {
        let root = URL(filePath: NSTemporaryDirectory()).appendingPathComponent("AppFeature-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return .ephemeral(root: root)
    }

    @Test func taskBootstrapsQueriesStatusAndRebuildsWhenStoreMissing() async throws {
        let container = try makeContainer()
        let rebuilds = LockIsolated(0)
        let manifest = PackManifest(id: "fr.arcep", version: "2026-09-01", country: "FR", kind: .prefixes, prefixes: ["+33162*"])

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.extensionReloader = ExtensionReloader(reload: {}, getEnabledStatus: { .enabled })
            $0.rulesRepository = RulesRepository(fetchAll: { [] }, insert: { _ in }, delete: { _ in }, update: { _ in })
            $0.packsRepository = PacksRepository(fetchAll: { [] }, fetch: { _ in nil }, insert: { _ in }, setEnabled: { _, _ in }, delete: { _ in })
            $0.embeddedPacks = EmbeddedPacks { [manifest] }
            $0.packBootstrap = PackBootstrap { manifests in
                #expect(manifests == [manifest])
                return BootstrapSummary(unchanged: ["fr.arcep"])
            }
            $0.storeOrchestrator = StoreOrchestrator(
                rebuildAndReload: { fatalError("not used") },
                requestRebuild: { rebuilds.withValue { $0 += 1 } }
            )
            $0.sharedContainer = container
            $0.storeStatus = StoreStatusHub().client
        }
        store.exhaustivity = .off

        await store.send(.task) {
            $0.isCheckingStatus = true
        }
        // Status check, bootstrap and the status stream run concurrently :
        // assert on the outcome rather than on an arrival order.
        await waitUntil { rebuilds.value == 1 }
        await store.skipReceivedActions()
        #expect(store.state.extensionStatus == .enabled)
        #expect(store.state.isCheckingStatus == false)
    }

    @Test func taskSkipsRebuildWhenStoreIsCurrentAndBootstrapUnchanged() async throws {
        let container = try makeContainer()
        try StoreManifest(
            buildDate: Date(timeIntervalSince1970: 1_700_000_000),
            block: .init(count: 5, ranges: 1, bytes: 40, sha256: ""),
            ident: .init(count: 0, ranges: 0, bytes: 32, sha256: ""),
            sources: ["user"],
            lastReload: .init(date: Date(timeIntervalSince1970: 1_700_000_010), succeeded: true)
        ).write(to: container.manifestURL())
        let hub = StoreStatusHub()

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.extensionReloader = ExtensionReloader(reload: {}, getEnabledStatus: { .enabled })
            $0.rulesRepository = RulesRepository(fetchAll: { [] }, insert: { _ in }, delete: { _ in }, update: { _ in })
            $0.packsRepository = PacksRepository(fetchAll: { [] }, fetch: { _ in nil }, insert: { _ in }, setEnabled: { _, _ in }, delete: { _ in })
            $0.embeddedPacks = EmbeddedPacks { [] }
            $0.packBootstrap = PackBootstrap { _ in BootstrapSummary() }
            $0.storeOrchestrator = StoreOrchestrator(
                rebuildAndReload: { fatalError("not used") },
                requestRebuild: { Issue.record("rebuild must not run") }
            )
            $0.sharedContainer = container
            $0.storeStatus = hub.client
        }
        store.exhaustivity = .off

        await store.send(.task)
        // The persisted outcome seeds the status so Réglages shows it right away.
        let expected = StoreStatus.ready(numbers: 5, date: Date(timeIntervalSince1970: 1_700_000_010))
        await waitUntil { hub.current == expected }
        await store.skipReceivedActions()
        #expect(store.state.storeStatus == expected)
    }

    @Test func needsRebuildRules() {
        let ok = StoreManifest(
            buildDate: .init(), block: .empty, ident: .empty, sources: [],
            lastReload: .init(date: .init(), succeeded: true)
        )
        #expect(AppFeature.needsRebuild(bootstrap: BootstrapSummary(), manifest: ok) == false)
        #expect(AppFeature.needsRebuild(bootstrap: BootstrapSummary(installed: ["x"]), manifest: ok) == true)
        #expect(AppFeature.needsRebuild(bootstrap: BootstrapSummary(removed: ["x"]), manifest: ok) == true)
        #expect(AppFeature.needsRebuild(bootstrap: BootstrapSummary(), manifest: nil) == true)

        var legacy = ok
        legacy.formatVersion = 1
        #expect(AppFeature.needsRebuild(bootstrap: BootstrapSummary(), manifest: legacy) == true)

        var failed = ok
        failed.lastReload = .init(date: .init(), succeeded: false, failure: .extensionDisabled)
        #expect(AppFeature.needsRebuild(bootstrap: BootstrapSummary(), manifest: failed) == true)

        var neverReloaded = ok
        neverReloaded.lastReload = nil
        #expect(AppFeature.needsRebuild(bootstrap: BootstrapSummary(), manifest: neverReloaded) == true)
    }

    @Test func cycleEndLoadsRunReportAndRechecksStatus() async throws {
        let container = try makeContainer()
        let report = ExtensionRunReport(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_000_042),
            isIncremental: true,
            blockNumbers: 20_000_000,
            outcome: .completed
        )
        try report.write(to: container.extensionRunURL())

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.extensionReloader = ExtensionReloader(reload: {}, getEnabledStatus: { .disabled })
            $0.sharedContainer = container
        }
        store.exhaustivity = .off

        await store.send(.storeStatusChanged(.reloading(numbers: 20_000_000))) {
            $0.storeStatus = .reloading(numbers: 20_000_000)
        }
        let failed = StoreStatus.failed(.extensionDisabled, numbers: 20_000_000, date: Date(timeIntervalSince1970: 1_700_000_050))
        await store.send(.storeStatusChanged(failed)) {
            $0.storeStatus = failed
            $0.isCheckingStatus = true
        }
        await store.skipReceivedActions()
        #expect(store.state.lastExtensionRun == report)
        #expect(store.state.extensionStatus == .disabled)
        #expect(store.state.isCheckingStatus == false)
    }

    @Test func statusChangeWhileIdleDoesNotTriggerSideEffects() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        // Going from unknown straight to ready (seeded from the manifest at
        // launch) is not the end of a cycle : nothing to reload.
        let ready = StoreStatus.ready(numbers: 3, date: Date(timeIntervalSince1970: 1_700_000_000))
        await store.send(.storeStatusChanged(ready)) {
            $0.storeStatus = ready
        }
    }

    @Test func rebuildButtonRequestsRebuild() async {
        let rebuilds = LockIsolated(0)
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.storeOrchestrator = StoreOrchestrator(
                rebuildAndReload: { fatalError("not used") },
                requestRebuild: { rebuilds.withValue { $0 += 1 } }
            )
        }
        await store.send(.rebuildButtonTapped)
        await store.finish()
        #expect(rebuilds.value == 1)
    }

    @Test func statusCheckFailureClearsLoadingFlag() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.extensionReloader = ExtensionReloader(
                reload: { },
                getEnabledStatus: { throw EquatableError(message: "boom") }
            )
        }
        await store.send(.refreshStatusButtonTapped) { $0.isCheckingStatus = true }
        await store.receive(\.statusCheckFailed) {
            $0.isCheckingStatus = false
        }
    }
}
