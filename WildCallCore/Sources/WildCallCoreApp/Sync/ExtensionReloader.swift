import CallKit
import Dependencies
import Foundation

public enum ExtensionEnabledStatus: Sendable, Equatable {
    case enabled
    case disabled
    case unknown
}

public struct ExtensionReloader: Sendable {
    public var reload: @Sendable () async throws -> Void
    public var getEnabledStatus: @Sendable () async throws -> ExtensionEnabledStatus

    public init(
        reload: @escaping @Sendable () async throws -> Void,
        getEnabledStatus: @escaping @Sendable () async throws -> ExtensionEnabledStatus
    ) {
        self.reload = reload
        self.getEnabledStatus = getEnabledStatus
    }
}

extension ExtensionReloader {
    public static let extensionBundleIdentifier = "com.octiplex.wildcall.directory"

    public static let live = ExtensionReloader(
        reload: {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
                CXCallDirectoryManager.sharedInstance.reloadExtension(
                    withIdentifier: extensionBundleIdentifier
                ) { error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume() }
                }
            }
        },
        getEnabledStatus: {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ExtensionEnabledStatus, any Error>) in
                CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(
                    withIdentifier: extensionBundleIdentifier
                ) { status, error in
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    let mapped: ExtensionEnabledStatus
                    switch status {
                    case .enabled: mapped = .enabled
                    case .disabled: mapped = .disabled
                    case .unknown: mapped = .unknown
                    @unknown default: mapped = .unknown
                    }
                    cont.resume(returning: mapped)
                }
            }
        }
    )
}

extension ExtensionReloader: DependencyKey {
    public static let liveValue: ExtensionReloader = .live
    public static let testValue: ExtensionReloader = ExtensionReloader(
        reload: { unimplemented("ExtensionReloader.reload") },
        getEnabledStatus: { unimplemented("ExtensionReloader.getEnabledStatus", placeholder: .unknown) }
    )
}

extension DependencyValues {
    public var extensionReloader: ExtensionReloader {
        get { self[ExtensionReloader.self] }
        set { self[ExtensionReloader.self] = newValue }
    }
}
