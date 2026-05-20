import Dependencies
import Foundation
import IssueReporting

public struct SyncSummary: Equatable, Sendable {
    public let added: [String]
    public let upgraded: [String]
    public let unchanged: [String]
    public let failed: [Failure]

    public struct Failure: Equatable, Sendable {
        public let packId: String
        public let reason: String  // human-readable for logs

        public init(packId: String, reason: String) {
            self.packId = packId
            self.reason = reason
        }
    }

    public init(
        added: [String] = [],
        upgraded: [String] = [],
        unchanged: [String] = [],
        failed: [Failure] = []
    ) {
        self.added = added
        self.upgraded = upgraded
        self.unchanged = unchanged
        self.failed = failed
    }

    public var didChangeAnything: Bool { !added.isEmpty || !upgraded.isEmpty }
}

public enum SyncError: Error, Equatable {
    case indexFetchFailed(String)
}

public struct PackSyncCoordinator: Sendable {
    public var sync: @Sendable () async throws -> SyncSummary

    public init(sync: @escaping @Sendable () async throws -> SyncSummary) {
        self.sync = sync
    }
}

extension PackSyncCoordinator {
    public static let live = PackSyncCoordinator {
        @Dependency(\.packIndexFetcher) var indexFetcher
        @Dependency(\.packFetcher) var packFetcher
        @Dependency(\.packLoader) var loader
        @Dependency(\.packsRepository) var packsRepo
        @Dependency(\.rulesRepository) var rulesRepo
        @Dependency(\.storeOrchestrator) var orchestrator
        @Dependency(\.date.now) var now

        let index: PackIndex
        do {
            index = try await indexFetcher.fetch()
        } catch {
            throw SyncError.indexFetchFailed(String(describing: error))
        }

        var added: [String] = []
        var upgraded: [String] = []
        var unchanged: [String] = []
        var failed: [SyncSummary.Failure] = []

        for entry in index.packs {
            let installed = try? await packsRepo.fetch(entry.id)
            if installed?.version == entry.version {
                unchanged.append(entry.id)
                continue
            }

            let archiveData: Data
            do {
                archiveData = try await packFetcher.fetch(entry.url)
            } catch {
                failed.append(.init(packId: entry.id, reason: "fetch: \(error)"))
                continue
            }

            let result = loader.loadFromArchive(archiveData, OctiplexTrust.publicKey, now)
            let loaded: LoadedPack
            switch result {
            case .success(let value):
                loaded = value
            case .failure(let error):
                failed.append(.init(packId: entry.id, reason: "load: \(error)"))
                continue
            }

            // Guard against id/version drift between index and signed manifest:
            // the manifest inside the .wildcallpack is the source of truth.
            guard loaded.manifest.id == entry.id else {
                failed.append(.init(packId: entry.id, reason: "manifest id mismatch (index=\(entry.id), pack=\(loaded.manifest.id))"))
                continue
            }

            let previouslyEnabled = installed?.enabled ?? true
            if installed != nil {
                let allRules = try await rulesRepo.fetchAll()
                for rule in allRules where rule.source == .pack(packId: entry.id) {
                    try await rulesRepo.delete(rule.id)
                }
                try await packsRepo.delete(entry.id)
                upgraded.append(entry.id)
            } else {
                added.append(entry.id)
            }

            for rule in loaded.rules {
                try await rulesRepo.insert(rule)
            }
            try await packsRepo.insert(
                InstalledPack(
                    id: loaded.manifest.id,
                    version: loaded.manifest.version,
                    country: loaded.manifest.country,
                    enabled: previouslyEnabled,
                    installedAt: now
                )
            )
        }

        let summary = SyncSummary(added: added, upgraded: upgraded, unchanged: unchanged, failed: failed)
        if summary.didChangeAnything {
            _ = try await orchestrator.rebuildAndReload()
        }
        return summary
    }
}

extension PackSyncCoordinator: DependencyKey {
    public static let liveValue: PackSyncCoordinator = .live
    public static let testValue: PackSyncCoordinator = PackSyncCoordinator {
        unimplemented("PackSyncCoordinator.sync", placeholder: SyncSummary())
    }
}

extension DependencyValues {
    public var packSyncCoordinator: PackSyncCoordinator {
        get { self[PackSyncCoordinator.self] }
        set { self[PackSyncCoordinator.self] = newValue }
    }
}
