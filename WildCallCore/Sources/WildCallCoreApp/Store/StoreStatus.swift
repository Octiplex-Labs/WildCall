import Dependencies
import Foundation
import Synchronization

/// What the shared store / extension pipeline is doing right now. Published
/// by `StoreOrchestrator`, observed by `AppFeature` so every screen can show
/// "iOS is ingesting N numbers" or "the last reload failed because…".
public enum StoreStatus: Equatable, Sendable {
    case unknown
    case building
    case reloading(numbers: Int)
    case ready(numbers: Int, date: Date)
    case failed(ReloadFailure, numbers: Int, date: Date)

    public var isBusy: Bool {
        switch self {
        case .building, .reloading: return true
        default: return false
        }
    }
}

public struct StoreStatusClient: Sendable {
    public var current: @Sendable () -> StoreStatus
    public var set: @Sendable (StoreStatus) -> Void
    /// Yields the current value immediately, then every change.
    public var stream: @Sendable () -> AsyncStream<StoreStatus>

    public init(
        current: @escaping @Sendable () -> StoreStatus,
        set: @escaping @Sendable (StoreStatus) -> Void,
        stream: @escaping @Sendable () -> AsyncStream<StoreStatus>
    ) {
        self.current = current
        self.set = set
        self.stream = stream
    }
}

public final class StoreStatusHub: Sendable {
    private struct State {
        var status: StoreStatus = .unknown
        var continuations: [UUID: AsyncStream<StoreStatus>.Continuation] = [:]
    }

    private let state = Mutex(State())

    public init(initial: StoreStatus = .unknown) {
        state.withLock { $0.status = initial }
    }

    public var current: StoreStatus {
        state.withLock { $0.status }
    }

    public func set(_ status: StoreStatus) {
        let continuations = state.withLock { state -> [AsyncStream<StoreStatus>.Continuation] in
            state.status = status
            return Array(state.continuations.values)
        }
        for continuation in continuations {
            continuation.yield(status)
        }
    }

    public func stream() -> AsyncStream<StoreStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            let initial = state.withLock { state -> StoreStatus in
                state.continuations[id] = continuation
                return state.status
            }
            continuation.yield(initial)
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.continuations.removeValue(forKey: id) }
            }
        }
    }

    public var client: StoreStatusClient {
        StoreStatusClient(
            current: { self.current },
            set: { self.set($0) },
            stream: { self.stream() }
        )
    }
}

extension StoreStatusClient: DependencyKey {
    public static let liveValue: StoreStatusClient = StoreStatusHub().client
    /// Tests get a real hub too : it is pure in-memory state and most
    /// features only need it to not crash when the orchestrator publishes.
    public static var testValue: StoreStatusClient { StoreStatusHub().client }
}

extension DependencyValues {
    public var storeStatus: StoreStatusClient {
        get { self[StoreStatusClient.self] }
        set { self[StoreStatusClient.self] = newValue }
    }
}
