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
            case exactInvalid
            case exactValid(E164)
            case wildcardInvalid(ParseError)
            case wildcardValid(prefix: E164Prefix, expandedCount: Int)

            public var isValid: Bool {
                switch self {
                case .exactValid, .wildcardValid: return true
                default: return false
                }
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
    @Dependency(\.wildcardParser) var wildcardParser
    @Dependency(\.wildcardExpander) var wildcardExpander
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
                    normalizer: normalizer,
                    parser: wildcardParser,
                    expander: wildcardExpander
                )
                return .none

            case .binding:
                return .none

            case .saveButtonTapped:
                guard let kind = Self.ruleKind(from: state.validation) else { return .none }
                state.isSaving = true
                let rule = BlockRule(
                    id: uuid(),
                    kind: kind,
                    source: .user,
                    action: state.action,
                    countryCode: state.countryCode,
                    label: state.label.isEmpty ? nil : state.label,
                    createdAt: now
                )
                return .run { [repository = repository, orchestrator = orchestrator] send in
                    do {
                        try await repository.insert(rule)
                        await orchestrator.requestRebuild()
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
        normalizer: PhoneNormalizer,
        parser: WildcardParser,
        expander: WildcardExpander
    ) -> State.Validation {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        if trimmed.contains("*") {
            switch parser.parse(trimmed, region) {
            case .success(let prefix):
                return .wildcardValid(prefix: prefix, expandedCount: expander.count(prefix))
            case .failure(let error):
                return .wildcardInvalid(error)
            }
        } else {
            do {
                let e164 = try normalizer.normalize(trimmed, region)
                return .exactValid(e164)
            } catch {
                return .exactInvalid
            }
        }
    }

    static func ruleKind(from validation: State.Validation) -> RuleKind? {
        switch validation {
        case .exactValid(let e164): return .exact(e164)
        case .wildcardValid(let prefix, _): return .prefix(prefix)
        default: return nil
        }
    }
}

public struct EquatableError: Error, Equatable, Sendable {
    public let message: String
    public init(_ error: any Error) { self.message = String(describing: error) }
    public init(message: String) { self.message = message }
}
