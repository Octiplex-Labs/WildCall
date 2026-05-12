import Foundation
import Testing
import ComposableArchitecture
import WildCallCoreShared
@testable import WildCallCoreApp

@MainActor
@Suite struct AddRuleFeatureTests {
    @Test func validationFlipsAsUserTypes() async {
        let store = TestStore(initialState: AddRuleFeature.State()) {
            AddRuleFeature()
        } withDependencies: {
            $0.phoneNormalizer = PhoneNormalizer(
                normalize: { raw, _ in
                    if raw == "0612345678" { return E164(33_612_345_678)! }
                    throw PhoneNormalizer.Failure.unparsable
                },
                validate: { _, _ in true },
                format: { e164 in "+\(e164.value)" }
            )
        }

        await store.send(.binding(.set(\.rawNumber, "abc"))) {
            $0.rawNumber = "abc"
            $0.validation = .invalid
        }

        await store.send(.binding(.set(\.rawNumber, "0612345678"))) {
            $0.rawNumber = "0612345678"
            $0.validation = .valid(E164(33_612_345_678)!)
        }

        await store.send(.binding(.set(\.rawNumber, ""))) {
            $0.rawNumber = ""
            $0.validation = .empty
        }
    }

    @Test func saveButtonInsertsAndRebuilds() async {
        let inserted = LockIsolated([BlockRule]())
        let orchestratorCalls = LockIsolated(0)
        let fixedID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let store = TestStore(
            initialState: AddRuleFeature.State(
                rawNumber: "0612345678",
                countryCode: "FR",
                action: .block,
                label: "",
                validation: .valid(E164(33_612_345_678)!)
            )
        ) {
            AddRuleFeature()
        } withDependencies: {
            $0.phoneNormalizer = PhoneNormalizer(
                normalize: { _, _ in E164(33_612_345_678)! },
                validate: { _, _ in true },
                format: { _ in "" }
            )
            $0.rulesRepository = RulesRepository(
                fetchAll: { [] },
                insert: { rule in inserted.withValue { $0.append(rule) } },
                delete: { _ in },
                update: { _ in }
            )
            $0.storeOrchestrator = StoreOrchestrator(
                rebuildAndReload: {
                    orchestratorCalls.withValue { $0 += 1 }
                    return RebuildSummary(
                        blockCount: 1,
                        identCount: 0,
                        block: .init(count: 1, bytesWritten: 24, sha256: ""),
                        ident: .init(count: 0, bytesWritten: 24, sha256: "")
                    )
                }
            )
            $0.uuid = .constant(fixedID)
            $0.date = .constant(fixedDate)
        }

        let expectedRule = BlockRule(
            id: fixedID,
            kind: .exact(E164(33_612_345_678)!),
            source: .user,
            action: .block,
            countryCode: "FR",
            label: nil,
            createdAt: fixedDate
        )

        await store.send(.saveButtonTapped) {
            $0.isSaving = true
        }
        await store.receive(\.ruleBuilt) {
            $0.isSaving = false
        }
        await store.receive(\.delegate.saved)

        #expect(inserted.value == [expectedRule])
        #expect(orchestratorCalls.value == 1)
    }

    @Test func saveButtonDoesNothingWhenInvalid() async {
        let store = TestStore(
            initialState: AddRuleFeature.State(validation: .invalid)
        ) {
            AddRuleFeature()
        } withDependencies: {
            $0.phoneNormalizer = .testValue
            $0.rulesRepository = .testValue
            $0.storeOrchestrator = .testValue
        }
        await store.send(.saveButtonTapped)
    }
}

extension AddRuleFeature.State {
    init(
        rawNumber: String,
        countryCode: String,
        action: RuleAction,
        label: String,
        validation: Validation
    ) {
        self.init()
        self.rawNumber = rawNumber
        self.countryCode = countryCode
        self.action = action
        self.label = label
        self.validation = validation
    }

    init(validation: Validation) {
        self.init()
        self.validation = validation
    }
}
