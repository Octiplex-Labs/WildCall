import ComposableArchitecture
import Foundation
import IdentifiedCollections
import WildCallCoreShared

@Reducer
public struct PacksFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        public var packs: IdentifiedArrayOf<InstalledPack> = []
        public var togglingId: String? = nil
        public var isLoading: Bool = false

        public init(packs: IdentifiedArrayOf<InstalledPack> = []) {
            self.packs = packs
        }
    }

    public enum Action: Sendable {
        case task
        case packsLoaded([InstalledPack])
        case toggle(id: String, enabled: Bool)
        case toggleCompleted(id: String)
        case toggleFailed(id: String, EquatableError)
        case loadFailed(EquatableError)
    }

    @Dependency(\.packsRepository) var packsRepository
    @Dependency(\.storeOrchestrator) var orchestrator

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.isLoading = true
                return .run { [packsRepository = packsRepository] send in
                    do {
                        let packs = try await packsRepository.fetchAll()
                        await send(.packsLoaded(packs))
                    } catch {
                        await send(.loadFailed(EquatableError(error)))
                    }
                }

            case .packsLoaded(let packs):
                state.isLoading = false
                state.packs = IdentifiedArray(uniqueElements: packs)
                return .none

            case .loadFailed:
                state.isLoading = false
                return .none

            case .toggle(let id, let enabled):
                guard let index = state.packs.index(id: id) else { return .none }
                state.packs[index] = InstalledPack(
                    id: state.packs[index].id,
                    version: state.packs[index].version,
                    country: state.packs[index].country,
                    enabled: enabled,
                    installedAt: state.packs[index].installedAt
                )
                state.togglingId = id
                return .run { [packsRepository = packsRepository, orchestrator = orchestrator] send in
                    do {
                        try await packsRepository.setEnabled(id, enabled)
                        _ = try await orchestrator.rebuildAndReload()
                        await send(.toggleCompleted(id: id))
                    } catch {
                        await send(.toggleFailed(id: id, EquatableError(error)))
                    }
                }

            case .toggleCompleted(let id):
                if state.togglingId == id { state.togglingId = nil }
                return .none

            case .toggleFailed(let id, _):
                if state.togglingId == id { state.togglingId = nil }
                // Reload from source of truth on failure.
                return .send(.task)
            }
        }
    }
}

extension InstalledPack {
    public var displayCountry: String { country }
}
