import Foundation
import Testing
import ComposableArchitecture
@testable import WildCallCoreApp

@MainActor
@Suite struct AppFeatureTests {
    @Test func taskQueriesExtensionStatus() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.extensionReloader = ExtensionReloader(
                reload: { },
                getEnabledStatus: { .enabled }
            )
            $0.rulesRepository = RulesRepository(
                fetchAll: { [] }, insert: { _ in }, delete: { _ in }, update: { _ in }
            )
            $0.storeOrchestrator = .testValue
        }
        store.exhaustivity = .off

        await store.send(.task) {
            $0.isCheckingStatus = true
        }
        await store.receive(\.statusReceived) {
            $0.isCheckingStatus = false
            $0.extensionStatus = .enabled
        }
    }

    @Test func statusCheckFailureClearsLoadingFlag() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.extensionReloader = ExtensionReloader(
                reload: { },
                getEnabledStatus: { throw EquatableError(message: "boom") }
            )
            $0.rulesRepository = .testValue
            $0.storeOrchestrator = .testValue
        }
        store.exhaustivity = .off

        await store.send(.task) { $0.isCheckingStatus = true }
        await store.receive(\.statusCheckFailed) {
            $0.isCheckingStatus = false
        }
    }
}
