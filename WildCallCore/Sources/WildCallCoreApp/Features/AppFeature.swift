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

        public init() {}
    }

    public enum Action: Sendable {
        case task
        case statusReceived(ExtensionEnabledStatus)
        case statusCheckFailed(EquatableError)
        case refreshStatusButtonTapped
        case openSettingsButtonTapped
        case rules(RulesFeature.Action)
        case packs(PacksFeature.Action)
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

            case .rules:
                return .none

            case .packs:
                return .none
            }
        }
    }
}
