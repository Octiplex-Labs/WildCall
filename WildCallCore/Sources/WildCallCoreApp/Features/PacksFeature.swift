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
        public var isSyncing: Bool = false
        public var lastSync: Date? = nil
        public var lastSyncSummary: SyncSummary? = nil
        public var lastSyncError: EquatableError? = nil
        public var exportFile: URL? = nil
        public var isExporting: Bool = false
        @Presents public var urlImportPresentation: PackURLImportFeature.State?

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
        case syncButtonTapped
        case syncCompleted(SyncSummary, Date)
        case syncFailed(EquatableError)
        case addByURLTapped
        case urlImportPresentation(PresentationAction<PackURLImportFeature.Action>)
        case exportButtonTapped
        case exportPrepared(URL)
        case exportFailed(EquatableError)
        case exportFileConsumed
    }

    @Dependency(\.packsRepository) var packsRepository
    @Dependency(\.rulesRepository) var rulesRepository
    @Dependency(\.storeOrchestrator) var orchestrator
    @Dependency(\.packSyncCoordinator) var syncCoordinator
    @Dependency(\.date.now) var now

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
                        await orchestrator.requestRebuild()
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

            case .syncButtonTapped:
                guard !state.isSyncing else { return .none }
                state.isSyncing = true
                state.lastSyncError = nil
                return .run { [syncCoordinator = syncCoordinator, now = now] send in
                    do {
                        let summary = try await syncCoordinator.sync()
                        await send(.syncCompleted(summary, now))
                    } catch {
                        await send(.syncFailed(EquatableError(error)))
                    }
                }

            case .syncCompleted(let summary, let date):
                state.isSyncing = false
                state.lastSync = date
                state.lastSyncSummary = summary
                // Reload packs in case the sync added/upgraded entries.
                return .send(.task)

            case .syncFailed(let error):
                state.isSyncing = false
                state.lastSyncError = error
                return .none

            case .addByURLTapped:
                state.urlImportPresentation = PackURLImportFeature.State()
                return .none

            case .urlImportPresentation(.presented(.delegate(.finished))):
                state.urlImportPresentation = nil
                return .send(.task)  // refresh after URL import

            case .urlImportPresentation:
                return .none

            case .exportButtonTapped:
                guard !state.isExporting else { return .none }
                state.isExporting = true
                return .run { [rulesRepository = rulesRepository, now = now] send in
                    do {
                        let rules = try await rulesRepository.fetchAll()
                        let export = RulesExport.build(from: rules, at: now)
                        let data = try export.encoded()
                        let url = URL(filePath: NSTemporaryDirectory())
                            .appendingPathComponent("WildCall-rules.json")
                        try data.write(to: url)
                        await send(.exportPrepared(url))
                    } catch {
                        await send(.exportFailed(EquatableError(error)))
                    }
                }

            case .exportPrepared(let url):
                state.isExporting = false
                state.exportFile = url
                return .none

            case .exportFailed:
                state.isExporting = false
                return .none

            case .exportFileConsumed:
                state.exportFile = nil
                return .none
            }
        }
        .ifLet(\.$urlImportPresentation, action: \.urlImportPresentation) {
            PackURLImportFeature()
        }
    }
}

extension InstalledPack {
    public var displayCountry: String { country }
}
