import Dependencies
import Foundation
import WildCallCoreShared

/// Idempotent installer for embedded packs. Runs at every launch with the
/// manifests bundled in the .app :
/// - missing pack → installed, enabled;
/// - installed at an older version → replaced (user enable/disable kept);
/// - installed at the same or a newer version (a remote sync may be ahead
///   of the bundle) → untouched;
/// - packs listed in `supersedes` → removed along with their rules.
public struct PackBootstrap: Sendable {
    public var run: @Sendable (_ manifests: [PackManifest]) async throws -> BootstrapSummary

    public init(run: @escaping @Sendable ([PackManifest]) async throws -> BootstrapSummary) {
        self.run = run
    }
}

public struct BootstrapSummary: Equatable, Sendable {
    public let installed: [String]   // pack ids newly installed this run
    public let upgraded: [String]    // pack ids whose version changed
    public let unchanged: [String]   // pack ids already at the manifest version or newer
    public let removed: [String]     // superseded pack ids that were uninstalled

    public init(
        installed: [String] = [],
        upgraded: [String] = [],
        unchanged: [String] = [],
        removed: [String] = []
    ) {
        self.installed = installed
        self.upgraded = upgraded
        self.unchanged = unchanged
        self.removed = removed
    }

    public var didChangeAnything: Bool {
        !installed.isEmpty || !upgraded.isEmpty || !removed.isEmpty
    }
}

extension PackBootstrap {
    public static let live = PackBootstrap { manifests in
        @Dependency(\.packLoader) var loader
        @Dependency(\.packsRepository) var packsRepo
        @Dependency(\.rulesRepository) var rulesRepo
        @Dependency(\.date.now) var now

        var installed: [String] = []
        var upgraded: [String] = []
        var unchanged: [String] = []
        var removed: [String] = []

        for manifest in manifests {
            for supersededId in manifest.supersedes ?? [] where supersededId != manifest.id {
                guard try await packsRepo.fetch(supersededId) != nil else { continue }
                try await Self.uninstall(packId: supersededId, packsRepo: packsRepo, rulesRepo: rulesRepo)
                removed.append(supersededId)
            }

            let existing = try await packsRepo.fetch(manifest.id)
            var enabled = true

            if let existing {
                guard Self.isNewer(manifest.version, than: existing.version) else {
                    unchanged.append(manifest.id)
                    continue
                }
                enabled = existing.enabled
                try await Self.uninstall(packId: manifest.id, packsRepo: packsRepo, rulesRepo: rulesRepo)
                upgraded.append(manifest.id)
            } else {
                installed.append(manifest.id)
            }

            let rules = loader.load(manifest, now)
            for rule in rules {
                try await rulesRepo.insert(rule)
            }
            try await packsRepo.insert(
                InstalledPack(
                    id: manifest.id,
                    version: manifest.version,
                    country: manifest.country,
                    enabled: enabled,
                    installedAt: now
                )
            )
        }

        return BootstrapSummary(installed: installed, upgraded: upgraded, unchanged: unchanged, removed: removed)
    }

    static func uninstall(packId: String, packsRepo: PacksRepository, rulesRepo: RulesRepository) async throws {
        let allRules = try await rulesRepo.fetchAll()
        for rule in allRules where rule.source == .pack(packId: packId) {
            try await rulesRepo.delete(rule.id)
        }
        try await packsRepo.delete(packId)
    }

    /// Pack versions are ISO dates (`2026-09-01`), so lexical order is
    /// chronological order. Falls back to plain string comparison for
    /// anything else, which is still deterministic.
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        candidate.compare(installed, options: [.numeric]) == .orderedDescending
    }
}

extension PackBootstrap: DependencyKey {
    public static let liveValue: PackBootstrap = .live
    public static let testValue: PackBootstrap = PackBootstrap { _ in
        unimplemented("PackBootstrap.run", placeholder: BootstrapSummary())
    }
}

extension DependencyValues {
    public var packBootstrap: PackBootstrap {
        get { self[PackBootstrap.self] }
        set { self[PackBootstrap.self] = newValue }
    }
}
