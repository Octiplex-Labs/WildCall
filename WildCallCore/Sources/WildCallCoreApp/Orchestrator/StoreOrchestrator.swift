import Dependencies
import Foundation
import WildCallCoreShared

public struct RebuildSummary: Equatable, Sendable {
    public let blockCount: Int
    public let identCount: Int
    public let block: BlobBuildSummary
    public let ident: BlobBuildSummary

    public init(
        blockCount: Int,
        identCount: Int,
        block: BlobBuildSummary,
        ident: BlobBuildSummary
    ) {
        self.blockCount = blockCount
        self.identCount = identCount
        self.block = block
        self.ident = ident
    }
}

public struct StoreOrchestrator: Sendable {
    public var rebuildAndReload: @Sendable () async throws -> RebuildSummary

    public init(rebuildAndReload: @escaping @Sendable () async throws -> RebuildSummary) {
        self.rebuildAndReload = rebuildAndReload
    }
}

extension StoreOrchestrator {
    public static func live(
        repository: RulesRepository,
        container: SharedContainer,
        reloader: ExtensionReloader,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> StoreOrchestrator {
        StoreOrchestrator(
            rebuildAndReload: {
                let rules = try await repository.fetchAll()
                let (blockNumbers, identEntries) = Self.split(rules: rules)

                let blockURL = try container.blockStoreURL()
                let identURL = try container.identStoreURL()
                let manifestURL = try container.manifestURL()

                let blockSummary = try BlockStoreBuilder().build(numbers: blockNumbers, to: blockURL)
                let identSummary = try IdentStoreBuilder().build(entries: identEntries, to: identURL)

                let manifest = StoreManifest(
                    buildDate: now(),
                    block: .init(count: blockSummary.count, bytes: blockSummary.bytesWritten, sha256: blockSummary.sha256),
                    ident: .init(count: identSummary.count, bytes: identSummary.bytesWritten, sha256: identSummary.sha256),
                    sources: ["user"]
                )
                try manifest.write(to: manifestURL)

                try await reloader.reload()

                return RebuildSummary(
                    blockCount: blockSummary.count,
                    identCount: identSummary.count,
                    block: blockSummary,
                    ident: identSummary
                )
            }
        )
    }

    static func split(rules: [BlockRule]) -> (numbers: [Int64], entries: [IdentEntry]) {
        var numbers: [Int64] = []
        var entries: [IdentEntry] = []
        numbers.reserveCapacity(rules.count)
        for rule in rules {
            guard case .exact(let e164) = rule.kind else { continue }
            switch rule.action {
            case .block:
                numbers.append(e164.value)
            case .identify:
                let label = rule.label ?? "WildCall"
                entries.append(IdentEntry(number: e164.value, label: label))
            }
        }
        return (numbers, entries)
    }
}

extension StoreOrchestrator: DependencyKey {
    public static let liveValue: StoreOrchestrator = {
        @Dependency(\.sharedContainer) var container
        @Dependency(\.rulesRepository) var repository
        @Dependency(\.extensionReloader) var reloader
        return .live(repository: repository, container: container, reloader: reloader)
    }()

    public static let testValue: StoreOrchestrator = StoreOrchestrator(
        rebuildAndReload: {
            unimplemented(
                "StoreOrchestrator.rebuildAndReload",
                placeholder: RebuildSummary(
                    blockCount: 0,
                    identCount: 0,
                    block: BlobBuildSummary(count: 0, bytesWritten: 0, sha256: ""),
                    ident: BlobBuildSummary(count: 0, bytesWritten: 0, sha256: "")
                )
            )
        }
    )
}

extension DependencyValues {
    public var storeOrchestrator: StoreOrchestrator {
        get { self[StoreOrchestrator.self] }
        set { self[StoreOrchestrator.self] = newValue }
    }
}
