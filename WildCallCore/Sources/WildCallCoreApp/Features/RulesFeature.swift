import ComposableArchitecture
import Foundation
import IdentifiedCollections
import WildCallCoreShared

@Reducer
public struct RulesFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        public var rules: IdentifiedArrayOf<BlockRule> = []
        public var packs: [InstalledPack] = []
        public var isLoading: Bool = false

        /// Rules the user added, newest first (repository order).
        public var userRules: [BlockRule] {
            rules.filter { $0.source == .user }
        }

        public var isEmpty: Bool { rules.isEmpty && packs.isEmpty }
        @Presents public var addRule: AddRuleFeature.State?

        public init() {}
    }

    public enum Action: Sendable {
        case task
        case rulesLoaded([BlockRule], packs: [InstalledPack])
        case loadFailed(EquatableError)
        case addButtonTapped
        case addRule(PresentationAction<AddRuleFeature.Action>)
        case deleteRequested(id: BlockRule.ID)
        case toggleActionRequested(id: BlockRule.ID)
        case mutationCompleted
        case mutationFailed(EquatableError)
        case syncFromEmptyStateTapped
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case syncRequested
        }
    }

    @Dependency(\.rulesRepository) var repository
    @Dependency(\.packsRepository) var packsRepository
    @Dependency(\.storeOrchestrator) var orchestrator

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.isLoading = true
                return .run { [repository = repository, packsRepository = packsRepository] send in
                    do {
                        let rules = try await repository.fetchAll()
                        let packs = try await packsRepository.fetchAll()
                        await send(.rulesLoaded(rules, packs: packs))
                    } catch {
                        await send(.loadFailed(EquatableError(error)))
                    }
                }

            case .rulesLoaded(let rules, let packs):
                state.isLoading = false
                state.rules = IdentifiedArray(uniqueElements: rules)
                state.packs = packs
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
                        await orchestrator.requestRebuild()
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
                        await orchestrator.requestRebuild()
                        await send(.mutationCompleted)
                    } catch {
                        await send(.mutationFailed(EquatableError(error)))
                    }
                }

            case .mutationCompleted, .mutationFailed:
                return .none

            case .syncFromEmptyStateTapped:
                return .send(.delegate(.syncRequested))

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$addRule, action: \.addRule) {
            AddRuleFeature()
        }
    }
}
