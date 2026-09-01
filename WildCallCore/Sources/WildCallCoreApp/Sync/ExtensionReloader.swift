import CallKit
import Dependencies
import Foundation
import WildCallCoreShared

public enum ExtensionEnabledStatus: Sendable, Equatable {
    case enabled
    case disabled
    case unknown
}

/// Typed mirror of `CXErrorCodeCallDirectoryManagerError`, so the UI can
/// explain what went wrong without depending on CallKit.
public enum ReloadFailure: Error, Equatable, Sendable, Codable {
    case extensionDisabled
    case noExtensionFound
    case currentlyLoading
    case loadingInterrupted
    case entriesOutOfOrder
    case duplicateEntries
    case maximumEntriesExceeded
    case unexpectedIncrementalRemoval
    case unknown(String)

    public init(_ error: any Error) {
        if let failure = error as? ReloadFailure {
            self = failure
            return
        }
        let nsError = error as NSError
        guard nsError.domain == CXErrorDomainCallDirectoryManager,
              let code = CXErrorCodeCallDirectoryManagerError.Code(rawValue: nsError.code)
        else {
            self = .unknown(String(describing: error))
            return
        }
        switch code {
        case .extensionDisabled: self = .extensionDisabled
        case .noExtensionFound: self = .noExtensionFound
        case .currentlyLoading: self = .currentlyLoading
        case .loadingInterrupted: self = .loadingInterrupted
        case .entriesOutOfOrder: self = .entriesOutOfOrder
        case .duplicateEntries: self = .duplicateEntries
        case .maximumEntriesExceeded: self = .maximumEntriesExceeded
        case .unexpectedIncrementalRemoval: self = .unexpectedIncrementalRemoval
        case .unknown: self = .unknown("CXErrorCodeCallDirectoryManagerError.unknown")
        @unknown default: self = .unknown("CXErrorCodeCallDirectoryManagerError(\(nsError.code))")
        }
    }
}

public struct ExtensionReloader: Sendable {
    /// Throws `ReloadFailure`.
    public var reload: @Sendable (ExtensionSlot) async throws -> Void
    public var getEnabledStatus: @Sendable (ExtensionSlot) async throws -> ExtensionEnabledStatus

    public init(
        reload: @escaping @Sendable (ExtensionSlot) async throws -> Void,
        getEnabledStatus: @escaping @Sendable (ExtensionSlot) async throws -> ExtensionEnabledStatus
    ) {
        self.reload = reload
        self.getEnabledStatus = getEnabledStatus
    }
}

extension ExtensionReloader {
    public static let live = ExtensionReloader(
        reload: { slot in
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
                CXCallDirectoryManager.sharedInstance.reloadExtension(
                    withIdentifier: slot.bundleIdentifier
                ) { error in
                    if let error { cont.resume(throwing: ReloadFailure(error)) }
                    else { cont.resume() }
                }
            }
        },
        getEnabledStatus: { slot in
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ExtensionEnabledStatus, any Error>) in
                CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(
                    withIdentifier: slot.bundleIdentifier
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
        reload: { _ in unimplemented("ExtensionReloader.reload") },
        getEnabledStatus: { _ in unimplemented("ExtensionReloader.getEnabledStatus", placeholder: .unknown) }
    )
}

extension DependencyValues {
    public var extensionReloader: ExtensionReloader {
        get { self[ExtensionReloader.self] }
        set { self[ExtensionReloader.self] = newValue }
    }
}
