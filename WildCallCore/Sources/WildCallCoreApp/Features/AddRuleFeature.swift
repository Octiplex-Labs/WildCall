import ComposableArchitecture
import Foundation
import WildCallCoreShared

@Reducer
public struct AddRuleFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        public var rawNumber: String = ""
        public var countryCode: String = "FR"
        public var action: RuleAction = .block
        public var label: String = ""
        public var validation: Validation = .empty
        public var isSaving: Bool = false

        public enum Validation: Equatable, Sendable {
            case empty
            case invalid
            case valid(E164)

            public var isValid: Bool {
                if case .valid = self { return true } else { return false }
            }
        }

        public init() {}
    }

    public enum Action: BindableAction, Sendable {
        case binding(BindingAction<State>)
        case saveButtonTapped
        case ruleBuilt(BlockRule)
        case saveFailed(EquatableError)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case saved
            case cancelled
        }
    }

    @Dependency(\.phoneNormalizer) var normalizer
    @Dependency(\.rulesRepository) var repository
    @Dependency(\.storeOrchestrator) var orchestrator
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding(\.rawNumber), .binding(\.countryCode):
                state.validation = Self.validate(
                    raw: state.rawNumber,
                    region: state.countryCode,
                    normalizer: normalizer
                )
                return .none

            case .binding:
                return .none

            case .saveButtonTapped:
                guard case .valid(let e164) = state.validation else { return .none }
                state.isSaving = true
                let rule = BlockRule(
                    id: uuid(),
                    kind: .exact(e164),
                    source: .user,
                    action: state.action,
                    countryCode: state.countryCode,
                    label: state.label.isEmpty ? nil : state.label,
                    createdAt: now
                )
                return .run { [normalizer = normalizer, repository = repository, orchestrator = orchestrator] send in
                    _ = normalizer  // suppress unused warning, keeps capture explicit
                    do {
                        try await repository.insert(rule)
                        _ = try await orchestrator.rebuildAndReload()
                        await send(.ruleBuilt(rule))
                    } catch {
                        await send(.saveFailed(EquatableError(error)))
                    }
                }

            case .ruleBuilt:
                state.isSaving = false
                return .send(.delegate(.saved))

            case .saveFailed:
                state.isSaving = false
                return .none

            case .delegate:
                return .none
            }
        }
    }

    static func validate(
        raw: String,
        region: String,
        normalizer: PhoneNormalizer
    ) -> State.Validation {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        do {
            let e164 = try normalizer.normalize(trimmed, region)
            return .valid(e164)
        } catch {
            return .invalid
        }
    }
}

public struct EquatableError: Error, Equatable, Sendable {
    public let message: String
    public init(_ error: any Error) { self.message = String(describing: error) }
    public init(message: String) { self.message = message }
}
