import Dependencies
import Foundation
import WildCallCoreShared

public struct SharedContainer: Sendable {
    public var rootURL: @Sendable () throws -> URL
    public var blockStoreURL: @Sendable (ExtensionSlot) throws -> URL
    public var identStoreURL: @Sendable (ExtensionSlot) throws -> URL
    public var extensionRunURL: @Sendable (ExtensionSlot) throws -> URL
    public var manifestURL: @Sendable () throws -> URL

    public init(
        rootURL: @escaping @Sendable () throws -> URL,
        blockStoreURL: @escaping @Sendable (ExtensionSlot) throws -> URL,
        identStoreURL: @escaping @Sendable (ExtensionSlot) throws -> URL,
        extensionRunURL: @escaping @Sendable (ExtensionSlot) throws -> URL,
        manifestURL: @escaping @Sendable () throws -> URL
    ) {
        self.rootURL = rootURL
        self.blockStoreURL = blockStoreURL
        self.identStoreURL = identStoreURL
        self.extensionRunURL = extensionRunURL
        self.manifestURL = manifestURL
    }

    public enum Failure: Error, Equatable {
        case appGroupUnavailable(identifier: String)
    }
}

extension SharedContainer {
    public static let appGroupIdentifier = BlockStoreFormat.appGroupIdentifier

    public static func live(appGroup: String = SharedContainer.appGroupIdentifier) -> SharedContainer {
        @Sendable func root() throws -> URL {
            guard let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            else {
                throw Failure.appGroupUnavailable(identifier: appGroup)
            }
            return url
        }
        return rooted(root)
    }

    public static func ephemeral(root: URL) -> SharedContainer {
        rooted { root }
    }

    private static func rooted(_ root: @escaping @Sendable () throws -> URL) -> SharedContainer {
        SharedContainer(
            rootURL: root,
            blockStoreURL: { try root().appendingPathComponent($0.blockFileName) },
            identStoreURL: { try root().appendingPathComponent($0.identFileName) },
            extensionRunURL: { try root().appendingPathComponent($0.extensionRunFileName) },
            manifestURL: { try root().appendingPathComponent(BlockStoreFormat.manifestFileName) }
        )
    }
}

extension SharedContainer: DependencyKey {
    public static let liveValue: SharedContainer = .live()
    public static let testValue: SharedContainer = SharedContainer(
        rootURL: { unimplemented("SharedContainer.rootURL", placeholder: URL(filePath: "/dev/null")) },
        blockStoreURL: { _ in unimplemented("SharedContainer.blockStoreURL", placeholder: URL(filePath: "/dev/null")) },
        identStoreURL: { _ in unimplemented("SharedContainer.identStoreURL", placeholder: URL(filePath: "/dev/null")) },
        extensionRunURL: { _ in unimplemented("SharedContainer.extensionRunURL", placeholder: URL(filePath: "/dev/null")) },
        manifestURL: { unimplemented("SharedContainer.manifestURL", placeholder: URL(filePath: "/dev/null")) }
    )
}

extension DependencyValues {
    public var sharedContainer: SharedContainer {
        get { self[SharedContainer.self] }
        set { self[SharedContainer.self] = newValue }
    }
}
