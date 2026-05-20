import ComposableArchitecture
import Dependencies
import Foundation
import Testing
@testable import WildCallCoreApp

@MainActor
@Suite struct PackURLImportFeatureTests {
    @Test func nonHttpsUrlIsRejected() async {
        let store = TestStore(initialState: PackURLImportFeature.State(urlInput: "http://example.com/pack")) {
            PackURLImportFeature()
        } withDependencies: {
            $0.packFetcher = .testValue
            $0.packLoader = .testValue
            $0.packsRepository = .testValue
            $0.rulesRepository = .testValue
            $0.storeOrchestrator = .testValue
            $0.trustedKeyStore = .testValue
            $0.date = .constant(Date())
        }
        store.exhaustivity = .off

        await store.send(.submitTapped)
        if case .failed = store.state.phase {
            // expected
        } else {
            Issue.record("expected .failed, got \(store.state.phase)")
        }
    }

    @Test func emptyUrlIsRejected() async {
        let store = TestStore(initialState: PackURLImportFeature.State(urlInput: "")) {
            PackURLImportFeature()
        } withDependencies: {
            $0.packFetcher = .testValue
            $0.packLoader = .testValue
            $0.packsRepository = .testValue
            $0.rulesRepository = .testValue
            $0.storeOrchestrator = .testValue
            $0.trustedKeyStore = .testValue
            $0.date = .constant(Date())
        }
        store.exhaustivity = .off

        await store.send(.submitTapped)
        if case .failed = store.state.phase {
            // expected
        } else {
            Issue.record("expected .failed, got \(store.state.phase)")
        }
    }

    @Test func downloadFailureSurfacesAsFailed() async {
        let store = TestStore(initialState: PackURLImportFeature.State(urlInput: "https://example.com/p.wildcallpack")) {
            PackURLImportFeature()
        } withDependencies: {
            $0.packFetcher = PackFetcher { _ in throw URLError(.notConnectedToInternet) }
            $0.packLoader = .testValue
            $0.packsRepository = .testValue
            $0.rulesRepository = .testValue
            $0.storeOrchestrator = .testValue
            $0.trustedKeyStore = .testValue
            $0.date = .constant(Date())
        }
        store.exhaustivity = .off

        await store.send(.submitTapped)
        await store.receive(\.downloadResult.failure)
        if case .failed = store.state.phase {
            // expected
        } else {
            Issue.record("expected .failed, got \(store.state.phase)")
        }
    }

    @Test func cancelDelegatesFinished() async {
        let store = TestStore(initialState: PackURLImportFeature.State()) {
            PackURLImportFeature()
        } withDependencies: {
            $0.packFetcher = .testValue
            $0.packLoader = .testValue
            $0.packsRepository = .testValue
            $0.rulesRepository = .testValue
            $0.storeOrchestrator = .testValue
            $0.trustedKeyStore = .testValue
            $0.date = .constant(Date())
        }

        await store.send(.cancelTapped)
        await store.receive(\.delegate.finished)
    }
}
