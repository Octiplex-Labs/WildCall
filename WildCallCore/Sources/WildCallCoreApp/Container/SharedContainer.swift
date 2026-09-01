import Dependencies
import Foundation
import WildCallCoreShared

public struct SharedContainer: Sendable {
    public var rootURL: @Sendable () throws -> URL
    public var blockStoreURL: @Sendable () throws -> URL
    public var identStoreURL: @Sendable () throws -> URL
    public var manifestURL: @Sendable () throws -> URL
    public var extensionRunURL: @Sendable () throws -> URL

    public init(
        rootURL: @escaping @Sendable () throws -> URL,
        blockStoreURL: @escaping @Sendable () throws -> URL,
        identStoreURL: @escaping @Sendable () throws -> URL,
        manifestURL: @escaping @Sendable () throws -> URL,
        extensionRunURL: @escaping @Sendable () throws -> URL
    ) {
        self.rootURL = rootURL
        self.blockStoreURL = blockStoreURL
        self.identStoreURL = identStoreURL
        self.manifestURL = manifestURL
        self.extensionRunURL = extensionRunURL
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
        return SharedContainer(
            rootURL: root,
            blockStoreURL: { try root().appendingPathComponent(BlockStoreFormat.blockFileName) },
            identStoreURL: { try root().appendingPathComponent(BlockStoreFormat.identFileName) },
            manifestURL: { try root().appendingPathComponent(BlockStoreFormat.manifestFileName) },
            extensionRunURL: { try root().appendingPathComponent(BlockStoreFormat.extensionRunFileName) }
        )
    }

    public static func ephemeral(root: URL) -> SharedContainer {
        SharedContainer(
            rootURL: { root },
            blockStoreURL: { root.appendingPathComponent(BlockStoreFormat.blockFileName) },
            identStoreURL: { root.appendingPathComponent(BlockStoreFormat.identFileName) },
            manifestURL: { root.appendingPathComponent(BlockStoreFormat.manifestFileName) },
            extensionRunURL: { root.appendingPathComponent(BlockStoreFormat.extensionRunFileName) }
        )
    }
}

extension SharedContainer: DependencyKey {
    public static let liveValue: SharedContainer = .live()
    public static let testValue: SharedContainer = SharedContainer(
        rootURL: { unimplemented("SharedContainer.rootURL", placeholder: URL(filePath: "/dev/null")) },
        blockStoreURL: { unimplemented("SharedContainer.blockStoreURL", placeholder: URL(filePath: "/dev/null")) },
        identStoreURL: { unimplemented("SharedContainer.identStoreURL", placeholder: URL(filePath: "/dev/null")) },
        manifestURL: { unimplemented("SharedContainer.manifestURL", placeholder: URL(filePath: "/dev/null")) },
        extensionRunURL: { unimplemented("SharedContainer.extensionRunURL", placeholder: URL(filePath: "/dev/null")) }
    )
}

extension DependencyValues {
    public var sharedContainer: SharedContainer {
        get { self[SharedContainer.self] }
        set { self[SharedContainer.self] = newValue }
    }
}
