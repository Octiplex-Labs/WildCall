import ComposableArchitecture
import Foundation
import WildCallCoreShared

@Reducer
public struct AppFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        public var rules: RulesFeature.State = .init()
        public var packs: PacksFeature.State = .init()
        public var extensionStatus: ExtensionEnabledStatus = .unknown
        public var isCheckingStatus: Bool = false
        public var storeStatus: StoreStatus = .unknown
        public var lastExtensionRun: ExtensionRunReport? = nil
        @Presents public var importPresentation: PackImportFeature.State?

        public init() {}
    }

    public enum Action: Sendable {
        case task
        case bootstrapFinished(BootstrapSummary)
        case bootstrapFailed(EquatableError)
        case statusReceived(ExtensionEnabledStatus)
        case statusCheckFailed(EquatableError)
        case refreshStatusButtonTapped
        case openSettingsButtonTapped
        case storeStatusChanged(StoreStatus)
        case extensionRunLoaded(ExtensionRunReport?)
        case rebuildButtonTapped
        case onOpenURL(URL)
        case rules(RulesFeature.Action)
        case packs(PacksFeature.Action)
        case importPresentation(PresentationAction<PackImportFeature.Action>)
    }

    private enum CancelID { case storeStatus }

    @Dependency(\.extensionReloader) var reloader
    @Dependency(\.embeddedPacks) var embeddedPacks
    @Dependency(\.packBootstrap) var bootstrap
    @Dependency(\.storeOrchestrator) var orchestrator
    @Dependency(\.storeStatus) var storeStatus
    @Dependency(\.sharedContainer) var container

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.rules, action: \.rules) {
            RulesFeature()
        }
        Scope(state: \.packs, action: \.packs) {
            PacksFeature()
        }
        mainReducer
            .ifLet(\.$importPresentation, action: \.importPresentation) {
                PackImportFeature()
            }
    }

    @ReducerBuilder<State, Action>
    var mainReducer: some ReducerOf<Self> {

        Reduce { state, action in
            switch action {
            case .task:
                state.isCheckingStatus = true
                return .merge(
                    checkExtensionStatus(),
                    runBootstrap(),
                    .run { [storeStatus = storeStatus] send in
                        for await status in storeStatus.stream() {
                            await send(.storeStatusChanged(status))
                        }
                    }
                    .cancellable(id: CancelID.storeStatus, cancelInFlight: true)
                )

            case .refreshStatusButtonTapped:
                state.isCheckingStatus = true
                return checkExtensionStatus()

            case .bootstrapFinished:
                // Rules and packs may have been inserted after the tabs
                // loaded their lists : refresh both.
                return .merge(.send(.rules(.task)), .send(.packs(.task)))

            case .bootstrapFailed:
                return .none

            case .statusReceived(let status):
                state.isCheckingStatus = false
                state.extensionStatus = status
                return .none

            case .statusCheckFailed:
                state.isCheckingStatus = false
                return .none

            case .openSettingsButtonTapped:
                // Side effect handled in the view layer via UIApplication.shared.open.
                return .none

            case .storeStatusChanged(let status):
                let wasBusy = state.storeStatus.isBusy
                state.storeStatus = status
                guard wasBusy, !status.isBusy else { return .none }
                // A cycle just ended : pick up what the extension reported,
                // and re-query the enabled status (a failure with
                // `extensionDisabled` means the banner must come back).
                state.isCheckingStatus = true
                return .merge(loadExtensionRun(), checkExtensionStatus())

            case .extensionRunLoaded(let report):
                state.lastExtensionRun = report
                return .none

            case .rebuildButtonTapped:
                return .run { [orchestrator = orchestrator] _ in
                    await orchestrator.requestRebuild()
                }

            case .onOpenURL(let url):
                guard url.pathExtension.lowercased() == "wildcallpack" else { return .none }
                state.importPresentation = PackImportFeature.State(fileURL: url)
                return .none

            case .importPresentation(.presented(.delegate(.finished))):
                state.importPresentation = nil
                return .merge(.send(.packs(.task)), .send(.rules(.task)))

            case .importPresentation:
                return .none

            case .rules(.delegate(.syncRequested)):
                // Empty-state shortcut in the Filtres tab: forward to the
                // Réglages tab's sync coordinator so the user can pull packs
                // without leaving the rules screen.
                return .send(.packs(.syncButtonTapped))

            case .packs(.syncCompleted):
                // After a successful sync the rules list needs to refresh
                // even when the user is on the Filtres tab (sync may have
                // added or upgraded a pack contributing new rules).
                return .send(.rules(.task))

            case .rules:
                return .none

            case .packs:
                return .none
            }
        }
    }

    private func checkExtensionStatus() -> Effect<Action> {
        .run { [reloader = reloader] send in
            do {
                let status = try await reloader.getEnabledStatus()
                await send(.statusReceived(status))
            } catch {
                await send(.statusCheckFailed(EquatableError(error)))
            }
        }
    }

    private func loadExtensionRun() -> Effect<Action> {
        .run { [container = container] send in
            let report = try? ExtensionRunReport.load(from: container.extensionRunURL())
            await send(.extensionRunLoaded(report))
        }
    }

    /// Installs or upgrades embedded packs, then rebuilds the shared store
    /// whenever something changed or the store on disk cannot be trusted
    /// (missing, older format, or last reload failed).
    private func runBootstrap() -> Effect<Action> {
        .run { [
            embeddedPacks = embeddedPacks,
            bootstrap = bootstrap,
            orchestrator = orchestrator,
            container = container,
            storeStatus = storeStatus
        ] send in
            let summary: BootstrapSummary
            do {
                summary = try await bootstrap.run(embeddedPacks.manifests())
            } catch {
                await send(.bootstrapFailed(EquatableError(error)))
                return
            }
            await send(.bootstrapFinished(summary))

            let manifest = (try? container.manifestURL()).flatMap { try? StoreManifest.load(from: $0) }
            if let manifest, let record = manifest.lastReload {
                let status: StoreStatus = record.succeeded
                    ? .ready(numbers: manifest.totalNumbers, date: record.date)
                    : .failed(record.failure ?? .unknown("?"), numbers: manifest.totalNumbers, date: record.date)
                if case .unknown = storeStatus.current() { storeStatus.set(status) }
            }
            if Self.needsRebuild(bootstrap: summary, manifest: manifest) {
                await orchestrator.requestRebuild()
            }
        }
    }

    static func needsRebuild(bootstrap: BootstrapSummary, manifest: StoreManifest?) -> Bool {
        if bootstrap.didChangeAnything { return true }
        guard let manifest else { return true }
        if manifest.formatVersion != StoreManifest.currentFormatVersion { return true }
        guard let lastReload = manifest.lastReload else { return true }
        return !lastReload.succeeded
    }
}
