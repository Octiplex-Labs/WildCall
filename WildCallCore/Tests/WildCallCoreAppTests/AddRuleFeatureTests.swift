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
            $0.wildcardParser = .live
            $0.wildcardExpander = .live
        }

        await store.send(.binding(.set(\.rawNumber, "abc"))) {
            $0.rawNumber = "abc"
            $0.validation = .exactInvalid
        }

        await store.send(.binding(.set(\.rawNumber, "0612345678"))) {
            $0.rawNumber = "0612345678"
            $0.validation = .exactValid(E164(33_612_345_678)!)
        }

        await store.send(.binding(.set(\.rawNumber, ""))) {
            $0.rawNumber = ""
            $0.validation = .empty
        }
    }

    @Test func validationDetectsWildcardPattern() async {
        let store = TestStore(initialState: AddRuleFeature.State()) {
            AddRuleFeature()
        } withDependencies: {
            $0.phoneNormalizer = .testValue
            $0.wildcardParser = .live
            $0.wildcardExpander = .live
        }

        await store.send(.binding(.set(\.rawNumber, "+33162999*"))) {
            $0.rawNumber = "+33162999*"
            $0.validation = .wildcardValid(
                prefix: E164Prefix(fixedDigits: "33162999", wildcardLength: 3),
                expandedCount: 1_000
            )
        }
    }

    @Test func validationSurfacesParseErrors() async {
        let store = TestStore(initialState: AddRuleFeature.State()) {
            AddRuleFeature()
        } withDependencies: {
            $0.phoneNormalizer = .testValue
            $0.wildcardParser = .live
            $0.wildcardExpander = .live
        }

        await store.send(.binding(.set(\.rawNumber, "+33162*"))) {
            $0.rawNumber = "+33162*"
            $0.validation = .wildcardInvalid(.fixedTooShort(minimum: 6))
        }
    }

    @Test func saveButtonInsertsExactRuleAndRebuilds() async {
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
                validation: .exactValid(E164(33_612_345_678)!)
            )
        ) {
            AddRuleFeature()
        } withDependencies: {
            $0.phoneNormalizer = .testValue
            $0.wildcardParser = .testValue
            $0.wildcardExpander = .testValue
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

    @Test func saveButtonInsertsPrefixRuleFromWildcardValidation() async {
        let inserted = LockIsolated([BlockRule]())
        let fixedID = UUID(uuidString: "00000000-0000-0000-0000-000000000456")!
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let prefix = E164Prefix(fixedDigits: "33162999", wildcardLength: 3)

        let store = TestStore(
            initialState: AddRuleFeature.State(
                rawNumber: "+33162999*",
                countryCode: "FR",
                action: .block,
                label: "",
                validation: .wildcardValid(prefix: prefix, expandedCount: 1_000)
            )
        ) {
            AddRuleFeature()
        } withDependencies: {
            $0.phoneNormalizer = .testValue
            $0.wildcardParser = .testValue
            $0.wildcardExpander = .testValue
            $0.rulesRepository = RulesRepository(
                fetchAll: { [] },
                insert: { rule in inserted.withValue { $0.append(rule) } },
                delete: { _ in },
                update: { _ in }
            )
            $0.storeOrchestrator = StoreOrchestrator(
                rebuildAndReload: {
                    RebuildSummary(
                        blockCount: 1_000,
                        identCount: 0,
                        block: .init(count: 1_000, bytesWritten: 0, sha256: ""),
                        ident: .init(count: 0, bytesWritten: 0, sha256: "")
                    )
                }
            )
            $0.uuid = .constant(fixedID)
            $0.date = .constant(fixedDate)
        }

        await store.send(.saveButtonTapped) {
            $0.isSaving = true
        }
        await store.receive(\.ruleBuilt) {
            $0.isSaving = false
        }
        await store.receive(\.delegate.saved)

        #expect(inserted.value.count == 1)
        if case .prefix(let saved) = inserted.value.first?.kind {
            #expect(saved == prefix)
        } else {
            Issue.record("expected a prefix rule, got \(String(describing: inserted.value.first))")
        }
    }

    @Test func saveButtonDoesNothingWhenInvalid() async {
        let store = TestStore(
            initialState: AddRuleFeature.State(validation: .exactInvalid)
        ) {
            AddRuleFeature()
        } withDependencies: {
            $0.phoneNormalizer = .testValue
            $0.wildcardParser = .testValue
            $0.wildcardExpander = .testValue
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
