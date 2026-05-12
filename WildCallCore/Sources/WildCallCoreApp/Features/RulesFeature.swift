import ComposableArchitecture
import Foundation
import IdentifiedCollections

@Reducer
public struct RulesFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        public var rules: IdentifiedArrayOf<BlockRule> = []
        public var isLoading: Bool = false
        @Presents public var addRule: AddRuleFeature.State?

        public init() {}
    }

    public enum Action: Sendable {
        case task
        case rulesLoaded([BlockRule])
        case loadFailed(EquatableError)
        case addButtonTapped
        case addRule(PresentationAction<AddRuleFeature.Action>)
        case deleteRequested(id: BlockRule.ID)
        case toggleActionRequested(id: BlockRule.ID)
        case mutationCompleted
        case mutationFailed(EquatableError)
    }

    @Dependency(\.rulesRepository) var repository
    @Dependency(\.storeOrchestrator) var orchestrator

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.isLoading = true
                return .run { [repository = repository] send in
                    do {
                        let rules = try await repository.fetchAll()
                        await send(.rulesLoaded(rules))
                    } catch {
                        await send(.loadFailed(EquatableError(error)))
                    }
                }

            case .rulesLoaded(let rules):
                state.isLoading = false
                state.rules = IdentifiedArray(uniqueElements: rules)
                return .none

            case .loadFailed:
                state.isLoading = false
                return .none

            case .addButtonTapped:
                state.addRule = AddRuleFeature.State()
                return .none

            case .addRule(.presented(.delegate(.saved))):
                state.addRule = nil
                return .send(.task)

            case .addRule(.presented(.delegate(.cancelled))), .addRule(.dismiss):
                state.addRule = nil
                return .none

            case .addRule:
                return .none

            case .deleteRequested(let id):
                state.rules.remove(id: id)
                return .run { [repository = repository, orchestrator = orchestrator] send in
                    do {
                        try await repository.delete(id)
                        _ = try await orchestrator.rebuildAndReload()
                        await send(.mutationCompleted)
                    } catch {
                        await send(.mutationFailed(EquatableError(error)))
                    }
                }

            case .toggleActionRequested(let id):
                guard let rule = state.rules[id: id] else { return .none }
                let toggled = BlockRule(
                    id: rule.id,
                    kind: rule.kind,
                    source: rule.source,
                    action: rule.action == .block ? .identify : .block,
                    countryCode: rule.countryCode,
                    label: rule.label,
                    createdAt: rule.createdAt
                )
                state.rules[id: id] = toggled
                return .run { [repository = repository, orchestrator = orchestrator] send in
                    do {
                        try await repository.update(toggled)
                        _ = try await orchestrator.rebuildAndReload()
                        await send(.mutationCompleted)
                    } catch {
                        await send(.mutationFailed(EquatableError(error)))
                    }
                }

            case .mutationCompleted, .mutationFailed:
                return .none
            }
        }
        .ifLet(\.$addRule, action: \.addRule) {
            AddRuleFeature()
        }
    }
}
