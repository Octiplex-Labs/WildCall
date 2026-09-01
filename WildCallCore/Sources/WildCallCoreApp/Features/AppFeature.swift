import ComposableArchitecture
import Foundation
import WildCallCoreShared

@Reducer
public struct AppFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        public var rules: RulesFeature.State = .init()
        public var packs: PacksFeature.State = .init()
        /// Enabled status per extension slot index.
        public var extensionStatuses: [Int: ExtensionEnabledStatus] = [:]
        public var isCheckingStatus: Bool = false
        public var storeStatus: StoreStatus = .unknown
        /// Last run report per slot index.
        public var lastExtensionRuns: [Int: ExtensionRunReport] = [:]
        @Presents public var importPresentation: PackImportFeature.State?

        public init() {}

        /// Slots iOS reports as enabled.
        public var enabledSlots: [ExtensionSlot] {
            ExtensionSlot.all.filter { extensionStatuses[$0.index] == .enabled }
        }

        /// Slots the user still has to switch on in Réglages.
        public var disabledSlots: [ExtensionSlot] {
            ExtensionSlot.all.filter { extensionStatuses[$0.index] == .disabled }
        }

        public var allSlotsEnabled: Bool {
            enabledSlots.count == ExtensionSlot.count
        }

        /// Aggregated status for the banner : enabled only when every slot
        /// is, disabled when at least one is, unknown otherwise.
        public var extensionStatus: ExtensionEnabledStatus {
            if allSlotsEnabled { return .enabled }
            if !disabledSlots.isEmpty { return .disabled }
            return .unknown
        }
    }

    public enum Action: Sendable {
        case task
        case bootstrapFinished(BootstrapSummary)
        case bootstrapFailed(EquatableError)
        case statusesReceived([Int: ExtensionEnabledStatus])
        case statusCheckFailed(EquatableError)
        case refreshStatusButtonTapped
        case openSettingsButtonTapped
        case storeStatusChanged(StoreStatus)
        case extensionRunsLoaded([Int: ExtensionRunReport])
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
                    checkExtensionStatuses(),
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
                return checkExtensionStatuses()

            case .bootstrapFinished:
                // Rules and packs may have been inserted after the tabs
                // loaded their lists : refresh both.
                return .merge(.send(.rules(.task)), .send(.packs(.task)))

            case .bootstrapFailed:
                return .none

            case .statusesReceived(let statuses):
                state.isCheckingStatus = false
                let wasComplete = state.allSlotsEnabled
                state.extensionStatuses = statuses
                // The user just switched the missing extensions on : retry
                // the cycle that failed on a disabled slot without asking.
                if state.allSlotsEnabled, !wasComplete,
                   case .failed(.extensionDisabled, _, _, _) = state.storeStatus {
                    return .run { [orchestrator = orchestrator] _ in
                        await orchestrator.requestRebuild()
                    }
                }
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
                // A cycle just ended : pick up what the extensions reported,
                // and re-query the enabled statuses (a failure with
                // `extensionDisabled` means the banner must come back).
                state.isCheckingStatus = true
                return .merge(loadExtensionRuns(), checkExtensionStatuses())

            case .extensionRunsLoaded(let reports):
                state.lastExtensionRuns = reports
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

            case .packs(.syncCompleted), .packs(.toggleCompleted):
                // Pack changes reshape the grouped list in the Filtres tab.
                return .send(.rules(.task))

            case .rules:
                return .none

            case .packs:
                return .none
            }
        }
    }

    private func checkExtensionStatuses() -> Effect<Action> {
        .run { [reloader = reloader] send in
            do {
                var statuses: [Int: ExtensionEnabledStatus] = [:]
                for slot in ExtensionSlot.all {
                    statuses[slot.index] = try await reloader.getEnabledStatus(slot)
                }
                await send(.statusesReceived(statuses))
            } catch {
                await send(.statusCheckFailed(EquatableError(error)))
            }
        }
    }

    private func loadExtensionRuns() -> Effect<Action> {
        .run { [container = container] send in
            var reports: [Int: ExtensionRunReport] = [:]
            for slot in ExtensionSlot.all {
                if let report = try? ExtensionRunReport.load(from: container.extensionRunURL(slot)) {
                    reports[slot.index] = report
                }
            }
            await send(.extensionRunsLoaded(reports))
        }
    }

    /// Installs or upgrades embedded packs, then rebuilds the shared store
    /// whenever something changed or the store on disk cannot be trusted
    /// (missing, older format, different slot layout, or last reload failed).
    private func runBootstrap() -> Effect<Action> {
        .run { [
            embeddedPacks = embeddedPacks,
            bootstrap = bootstrap,
            orchestrator = orchestrator,
            container = container,
            storeStatus = storeStatus
        ] send in
            let manifests = embeddedPacks.manifests()
            WildCallLog.info("Bootstrap: \(manifests.count) embedded pack(s): \(manifests.map { "\($0.id)@\($0.version)" }.joined(separator: ", "))")
            let summary: BootstrapSummary
            do {
                summary = try await bootstrap.run(manifests)
            } catch {
                WildCallLog.error("Bootstrap failed: \(error)")
                await send(.bootstrapFailed(EquatableError(error)))
                return
            }
            WildCallLog.info("Bootstrap: installed \(summary.installed), upgraded \(summary.upgraded), removed \(summary.removed), unchanged \(summary.unchanged)")
            await send(.bootstrapFinished(summary))

            let manifest = (try? container.manifestURL()).flatMap { try? StoreManifest.load(from: $0) }
            if let manifest, let record = manifest.lastReload {
                let status: StoreStatus = record.succeeded
                    ? .ready(numbers: manifest.totalNumbers, date: record.date)
                    : .failed(record.failure ?? .unknown("?"), numbers: manifest.totalNumbers, date: record.date, slot: record.slot)
                if case .unknown = storeStatus.current() { storeStatus.set(status) }
            }
            let needsRebuild = Self.needsRebuild(bootstrap: summary, manifest: manifest) || DebugProbe.forceRebuild
            WildCallLog.info("Bootstrap: store manifest \(manifest == nil ? "missing" : "v\(manifest!.formatVersion), \(manifest!.slots.count) slot(s)"), rebuild needed: \(needsRebuild)")
            if needsRebuild {
                await orchestrator.requestRebuild()
            }
        }
    }

    static func needsRebuild(bootstrap: BootstrapSummary, manifest: StoreManifest?) -> Bool {
        if bootstrap.didChangeAnything { return true }
        guard let manifest else { return true }
        if manifest.formatVersion != StoreManifest.currentFormatVersion { return true }
        if !manifest.matchesSlotLayout { return true }
        guard let lastReload = manifest.lastReload else { return true }
        return !lastReload.succeeded
    }
}
