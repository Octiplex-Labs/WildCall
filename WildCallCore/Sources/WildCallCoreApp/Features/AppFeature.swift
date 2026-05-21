import ComposableArchitecture
import Foundation

@Reducer
public struct AppFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        public var rules: RulesFeature.State = .init()
        public var packs: PacksFeature.State = .init()
        public var extensionStatus: ExtensionEnabledStatus = .unknown
        public var isCheckingStatus: Bool = false
        @Presents public var importPresentation: PackImportFeature.State?

        public init() {}
    }

    public enum Action: Sendable {
        case task
        case statusReceived(ExtensionEnabledStatus)
        case statusCheckFailed(EquatableError)
        case refreshStatusButtonTapped
        case openSettingsButtonTapped
        case onOpenURL(URL)
        case rules(RulesFeature.Action)
        case packs(PacksFeature.Action)
        case importPresentation(PresentationAction<PackImportFeature.Action>)
    }

    @Dependency(\.extensionReloader) var reloader

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
            case .task, .refreshStatusButtonTapped:
                state.isCheckingStatus = true
                return .run { [reloader = reloader] send in
                    do {
                        let status = try await reloader.getEnabledStatus()
                        await send(.statusReceived(status))
                    } catch {
                        await send(.statusCheckFailed(EquatableError(error)))
                    }
                }

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

            case .onOpenURL(let url):
                guard url.pathExtension.lowercased() == "wildcallpack" else { return .none }
                state.importPresentation = PackImportFeature.State(fileURL: url)
                return .none

            case .importPresentation(.presented(.delegate(.finished))):
                state.importPresentation = nil
                return .send(.packs(.task))  // refresh packs list after import

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
}
