import Foundation
import Testing
import ComposableArchitecture
import WildCallCoreShared
@testable import WildCallCoreApp

@MainActor
@Suite struct RulesFeatureTests {
    @Test func taskLoadsRulesFromRepository() async {
        let rule = BlockRule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            kind: .exact(E164(33_612_345_678)!),
            source: .user,
            action: .block,
            countryCode: "FR"
        )
        let store = TestStore(initialState: RulesFeature.State()) {
            RulesFeature()
        } withDependencies: {
            $0.rulesRepository = RulesRepository(
                fetchAll: { [rule] },
                insert: { _ in },
                delete: { _ in },
                update: { _ in }
            )
            $0.storeOrchestrator = .testValue
        }

        await store.send(.task) { $0.isLoading = true }
        await store.receive(\.rulesLoaded) {
            $0.isLoading = false
            $0.rules = [rule]
        }
    }

    @Test func deleteRequestedRemovesAndRebuilds() async {
        let rule = BlockRule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            kind: .exact(E164(33_612_345_678)!),
            source: .user,
            action: .block,
            countryCode: "FR"
        )
        let deletedIDs = LockIsolated([UUID]())
        let rebuilds = LockIsolated(0)

        let store = TestStore(initialState: RulesFeature.State()) {
            RulesFeature()
        } withDependencies: {
            $0.rulesRepository = RulesRepository(
                fetchAll: { [] },
                insert: { _ in },
                delete: { id in deletedIDs.withValue { $0.append(id) } },
                update: { _ in }
            )
            $0.storeOrchestrator = StoreOrchestrator(
                rebuildAndReload: {
                    rebuilds.withValue { $0 += 1 }
                    return RebuildSummary(
                        blockCount: 0, identCount: 0,
                        block: .init(count: 0, bytesWritten: 0, sha256: ""),
                        ident: .init(count: 0, bytesWritten: 0, sha256: "")
                    )
                }
            )
        }
        store.exhaustivity = .off

        await store.send(.rulesLoaded([rule])) {
            $0.rules = [rule]
        }
        await store.send(.deleteRequested(id: rule.id)) {
            $0.rules.remove(id: rule.id)
        }
        await store.receive(\.mutationCompleted)

        #expect(deletedIDs.value == [rule.id])
        #expect(rebuilds.value == 1)
    }

    @Test func toggleActionFlipsAndRebuilds() async {
        let original = BlockRule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
            kind: .exact(E164(33_612_345_678)!),
            source: .user,
            action: .block,
            countryCode: "FR"
        )
        let updates = LockIsolated([BlockRule]())

        let store = TestStore(
            initialState: RulesFeature.State(rules: [original])
        ) {
            RulesFeature()
        } withDependencies: {
            $0.rulesRepository = RulesRepository(
                fetchAll: { [] },
                insert: { _ in },
                delete: { _ in },
                update: { r in updates.withValue { $0.append(r) } }
            )
            $0.storeOrchestrator = StoreOrchestrator(
                rebuildAndReload: {
                    RebuildSummary(
                        blockCount: 0, identCount: 0,
                        block: .init(count: 0, bytesWritten: 0, sha256: ""),
                        ident: .init(count: 0, bytesWritten: 0, sha256: "")
                    )
                }
            )
        }
        store.exhaustivity = .off

        let flipped = BlockRule(
            id: original.id,
            kind: original.kind,
            source: original.source,
            action: .identify,
            countryCode: original.countryCode,
            label: original.label,
            createdAt: original.createdAt
        )
        await store.send(.toggleActionRequested(id: original.id)) {
            $0.rules[id: original.id] = flipped
        }
        await store.receive(\.mutationCompleted)

        #expect(updates.value.count == 1)
        #expect(updates.value.first?.action == .identify)
    }
}

extension RulesFeature.State {
    init(rules: [BlockRule]) {
        self.init()
        self.rules = .init(uniqueElements: rules)
    }
}
