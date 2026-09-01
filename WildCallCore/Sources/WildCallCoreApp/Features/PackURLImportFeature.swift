import ComposableArchitecture
import Foundation
import WildCallCoreShared

@Reducer
public struct PackURLImportFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        public var urlInput: String = ""
        public var phase: Phase = .idle

        public enum Phase: Equatable {
            case idle
            case downloading
            case awaitingTrust(manifest: PackManifest, fingerprint: String, archive: Data)
            case installing
            case failed(EquatableError)
            case finished
        }

        public init(urlInput: String = "", phase: Phase = .idle) {
            self.urlInput = urlInput
            self.phase = phase
        }

        public var isBusy: Bool {
            switch phase {
            case .downloading, .installing: return true
            default: return false
            }
        }
    }

    public enum Action: BindableAction, Sendable {
        case binding(BindingAction<State>)
        case submitTapped
        case downloadResult(Result<Data, EquatableError>)
        case previewReady(manifest: PackManifest, fingerprint: String, archive: Data)
        case trustAcceptTapped
        case trustRejectTapped
        case installResult(Result<Void, EquatableError>)
        case cancelTapped
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case finished
        }
    }

    @Dependency(\.packFetcher) var packFetcher
    @Dependency(\.packLoader) var loader
    @Dependency(\.packsRepository) var packsRepository
    @Dependency(\.rulesRepository) var rulesRepository
    @Dependency(\.storeOrchestrator) var orchestrator
    @Dependency(\.trustedKeyStore) var trustedKeyStore
    @Dependency(\.date.now) var now

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .submitTapped:
                let trimmed = state.urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: trimmed),
                      url.scheme?.lowercased() == "https"
                else {
                    state.phase = .failed(EquatableError(message: String(localized: "URL invalide (HTTPS requis)")))
                    return .none
                }
                state.phase = .downloading
                return .run { [packFetcher = packFetcher] send in
                    do {
                        let data = try await packFetcher.fetch(url)
                        await send(.downloadResult(.success(data)))
                    } catch {
                        await send(.downloadResult(.failure(EquatableError(error))))
                    }
                }

            case .downloadResult(.failure(let error)):
                state.phase = .failed(error)
                return .none

            case .downloadResult(.success(let data)):
                let archive = PackArchive()
                let manifest: PackManifest
                let contents: PackArchive.Contents
                do {
                    manifest = try archive.peekManifest(data)
                    contents = try archive.read(data)
                } catch {
                    state.phase = .failed(EquatableError(error))
                    return .none
                }
                guard let publisherKey = manifest.publisherKeyBytes() else {
                    state.phase = .failed(EquatableError(message: String(localized: "Le manifeste ne déclare pas de clé publique (champ publisherKey).")))
                    return .none
                }
                guard PackSignatureVerifier.live.verify(contents.manifest, contents.signature, publisherKey) else {
                    state.phase = .failed(EquatableError(message: String(localized: "Signature invalide pour la clé publique déclarée.")))
                    return .none
                }
                let fingerprint = OctiplexTrust.fingerprint(of: publisherKey)
                let packId = manifest.id
                return .run { [
                    trustedKeyStore = trustedKeyStore,
                    loader = loader,
                    packsRepository = packsRepository,
                    rulesRepository = rulesRepository,
                    orchestrator = orchestrator,
                    now = now,
                    manifest = manifest,
                    publisherKey = publisherKey,
                    fingerprint = fingerprint,
                    data = data,
                    packId = packId
                ] send in
                    do {
                        let pinned = try await trustedKeyStore.fetch(packId)
                        if let pinned, pinned.publicKey != publisherKey {
                            await send(.installResult(.failure(
                                EquatableError(message: String(localized: "La clé du publisher diffère du pin existant (\(pinned.fingerprint)). Refus pour raison de sécurité."))
                            )))
                            return
                        }
                        if pinned != nil {
                            try await Self.installAndRebuild(
                                data: data, trustedKey: publisherKey, loader: loader,
                                packsRepository: packsRepository, rulesRepository: rulesRepository,
                                orchestrator: orchestrator, now: now
                            )
                            await send(.installResult(.success(())))
                        } else {
                            await send(.previewReady(manifest: manifest, fingerprint: fingerprint, archive: data))
                        }
                    } catch {
                        await send(.installResult(.failure(EquatableError(error))))
                    }
                }

            case .previewReady(let manifest, let fingerprint, let archive):
                state.phase = .awaitingTrust(manifest: manifest, fingerprint: fingerprint, archive: archive)
                return .none

            case .trustAcceptTapped:
                guard case .awaitingTrust(let manifest, let fingerprint, let data) = state.phase else { return .none }
                guard let publisherKey = manifest.publisherKeyBytes() else {
                    state.phase = .failed(EquatableError(message: String(localized: "Clé publique disparue du manifeste.")))
                    return .none
                }
                state.phase = .installing
                return .run { [
                    trustedKeyStore = trustedKeyStore,
                    loader = loader,
                    packsRepository = packsRepository,
                    rulesRepository = rulesRepository,
                    orchestrator = orchestrator,
                    now = now,
                    manifest = manifest,
                    fingerprint = fingerprint,
                    publisherKey = publisherKey,
                    data = data
                ] send in
                    do {
                        try await Self.installAndRebuild(
                            data: data, trustedKey: publisherKey, loader: loader,
                            packsRepository: packsRepository, rulesRepository: rulesRepository,
                            orchestrator: orchestrator, now: now
                        )
                        try await trustedKeyStore.pin(TrustedKey(
                            packId: manifest.id,
                            publicKey: publisherKey,
                            fingerprint: fingerprint,
                            pinnedAt: now,
                            sourceURL: nil
                        ))
                        await send(.installResult(.success(())))
                    } catch {
                        await send(.installResult(.failure(EquatableError(error))))
                    }
                }

            case .trustRejectTapped:
                return .send(.delegate(.finished))

            case .installResult(.success):
                state.phase = .finished
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

    static func installAndRebuild(
        data: Data,
        trustedKey: Data,
        loader: PackLoader,
        packsRepository: PacksRepository,
        rulesRepository: RulesRepository,
        orchestrator: StoreOrchestrator,
        now: Date
    ) async throws {
        let result = loader.loadFromArchive(data, trustedKey, now)
        switch result {
        case .success(let loaded):
            try await PackImportFeature.install(
                loaded: loaded,
                packsRepository: packsRepository,
                rulesRepository: rulesRepository,
                now: now
            )
            await orchestrator.requestRebuild()
        case .failure(let err):
            throw EquatableError(err)
        }
    }
}
