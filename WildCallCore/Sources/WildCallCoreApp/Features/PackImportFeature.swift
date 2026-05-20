import ComposableArchitecture
import Foundation
import WildCallCoreShared

@Reducer
public struct PackImportFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        public let fileURL: URL
        public var phase: Phase = .reading

        public enum Phase: Equatable {
            case reading
            case awaitingConfirmation(LoadedPack)
            case installing
            case failed(EquatableError)
            case finished(SyncSummary.Failure?)  // .none if installed cleanly
        }

        public init(fileURL: URL, phase: Phase = .reading) {
            self.fileURL = fileURL
            self.phase = phase
        }
    }

    public enum Action: Sendable {
        case task
        case loadResult(Result<LoadedPack, EquatableError>)
        case confirmTapped
        case cancelTapped
        case installResult(Result<Void, EquatableError>)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case finished
        }
    }

    @Dependency(\.packLoader) var loader
    @Dependency(\.packsRepository) var packsRepository
    @Dependency(\.rulesRepository) var rulesRepository
    @Dependency(\.storeOrchestrator) var orchestrator
    @Dependency(\.date.now) var now

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                let url = state.fileURL
                return .run { [loader = loader, now = now] send in
                    do {
                        let data = try Self.readSecurityScoped(url: url)
                        let result = loader.loadFromArchive(data, OctiplexTrust.publicKey, now)
                        switch result {
                        case .success(let loaded):
                            await send(.loadResult(.success(loaded)))
                        case .failure(let err):
                            await send(.loadResult(.failure(EquatableError(err))))
                        }
                    } catch {
                        await send(.loadResult(.failure(EquatableError(error))))
                    }
                }

            case .loadResult(.success(let loaded)):
                state.phase = .awaitingConfirmation(loaded)
                return .none

            case .loadResult(.failure(let error)):
                state.phase = .failed(error)
                return .none

            case .confirmTapped:
                guard case .awaitingConfirmation(let loaded) = state.phase else { return .none }
                state.phase = .installing
                return .run { [
                    packsRepository = packsRepository,
                    rulesRepository = rulesRepository,
                    orchestrator = orchestrator,
                    now = now
                ] send in
                    do {
                        try await Self.install(
                            loaded: loaded,
                            packsRepository: packsRepository,
                            rulesRepository: rulesRepository,
                            now: now
                        )
                        _ = try await orchestrator.rebuildAndReload()
                        await send(.installResult(.success(())))
                    } catch {
                        await send(.installResult(.failure(EquatableError(error))))
                    }
                }

            case .installResult(.success):
                state.phase = .finished(nil)
                return .send(.delegate(.finished))

            case .installResult(.failure(let error)):
                state.phase = .failed(error)
                return .none

            case .cancelTapped:
                return .send(.delegate(.finished))

            case .delegate:
                return .none
            }
        }
    }

    static func readSecurityScoped(url: URL) throws -> Data {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    static func install(
        loaded: LoadedPack,
        packsRepository: PacksRepository,
        rulesRepository: RulesRepository,
        now: Date
    ) async throws {
        let id = loaded.manifest.id
        let previouslyEnabled = (try? await packsRepository.fetch(id))?.enabled ?? true

        if (try? await packsRepository.fetch(id)) != nil {
            let allRules = try await rulesRepository.fetchAll()
            for rule in allRules where rule.source == .pack(packId: id) {
                try await rulesRepository.delete(rule.id)
            }
            try await packsRepository.delete(id)
        }

        for rule in loaded.rules {
            try await rulesRepository.insert(rule)
        }
        try await packsRepository.insert(
            InstalledPack(
                id: id,
                version: loaded.manifest.version,
                country: loaded.manifest.country,
                enabled: previouslyEnabled,
                installedAt: now
            )
        )
    }
}
