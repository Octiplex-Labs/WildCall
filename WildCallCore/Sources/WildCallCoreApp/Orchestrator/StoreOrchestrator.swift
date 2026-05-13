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

public enum OrchestratorError: Error, Equatable, Sendable {
    case exceedsTotalQuota(expanded: Int, limit: Int)
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
        packsRepository: PacksRepository,
        container: SharedContainer,
        reloader: ExtensionReloader,
        expander: WildcardExpander,
        quotas: WildcardQuotas,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> StoreOrchestrator {
        StoreOrchestrator(
            rebuildAndReload: {
                let rules = try await repository.fetchAll()
                let packs = try await packsRepository.fetchAll()
                let activeRules = Self.filterByPackActivation(rules: rules, packs: packs)
                let (blockNumbers, identEntries) = try Self.split(
                    rules: activeRules,
                    expander: expander,
                    quotas: quotas
                )

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

    static func split(
        rules: [BlockRule],
        expander: WildcardExpander,
        quotas: WildcardQuotas
    ) throws -> (numbers: [Int64], entries: [IdentEntry]) {
        var numbers: [Int64] = []
        var entries: [IdentEntry] = []
        var userExpanded = 0
        numbers.reserveCapacity(rules.count)

        for rule in rules {
            switch rule.kind {
            case .exact(let e164):
                appendNumberOrEntry(value: e164.value, rule: rule, into: &numbers, entries: &entries)
            case .prefix(let prefix):
                let expanded = expander.expand(prefix)
                if case .user = rule.source {
                    userExpanded += expanded.count
                    if userExpanded > quotas.totalUser {
                        throw OrchestratorError.exceedsTotalQuota(
                            expanded: userExpanded,
                            limit: quotas.totalUser
                        )
                    }
                }
                for value in expanded {
                    appendNumberOrEntry(value: value, rule: rule, into: &numbers, entries: &entries)
                }
            }
        }
        return (numbers, entries)
    }

    static func filterByPackActivation(
        rules: [BlockRule],
        packs: [InstalledPack]
    ) -> [BlockRule] {
        let disabledIds = Set(packs.filter { !$0.enabled }.map(\.id))
        guard !disabledIds.isEmpty else { return rules }
        return rules.filter { rule in
            if case .pack(let id) = rule.source {
                return !disabledIds.contains(id)
            }
            return true
        }
    }

    private static func appendNumberOrEntry(
        value: Int64,
        rule: BlockRule,
        into numbers: inout [Int64],
        entries: inout [IdentEntry]
    ) {
        switch rule.action {
        case .block:
            numbers.append(value)
        case .identify:
            let label = rule.label ?? "WildCall"
            entries.append(IdentEntry(number: value, label: label))
        }
    }
}

extension StoreOrchestrator: DependencyKey {
    public static let liveValue: StoreOrchestrator = {
        @Dependency(\.sharedContainer) var container
        @Dependency(\.rulesRepository) var repository
        @Dependency(\.packsRepository) var packsRepository
        @Dependency(\.extensionReloader) var reloader
        @Dependency(\.wildcardExpander) var expander
        @Dependency(\.wildcardQuotas) var quotas
        return .live(
            repository: repository,
            packsRepository: packsRepository,
            container: container,
            reloader: reloader,
            expander: expander,
            quotas: quotas
        )
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
