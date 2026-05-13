import Dependencies
import Foundation
import WildCallCoreShared

/// Idempotent installer for embedded packs. Run once at app launch with the
/// list of bundled manifests; the bootstrap diffs each manifest against the
/// installed PackRecord (by id + version) and only writes when something
/// changed. Pre-existing user enable/disable choices are preserved when the
/// pack version is unchanged.
public struct PackBootstrap: Sendable {
    public var run: @Sendable (_ manifests: [PackManifest]) async throws -> BootstrapSummary

    public init(run: @escaping @Sendable ([PackManifest]) async throws -> BootstrapSummary) {
        self.run = run
    }
}

public struct BootstrapSummary: Equatable, Sendable {
    public let installed: [String]   // pack ids newly installed this run
    public let upgraded: [String]    // pack ids whose version changed
    public let unchanged: [String]   // pack ids already at the manifest version

    public init(installed: [String] = [], upgraded: [String] = [], unchanged: [String] = []) {
        self.installed = installed
        self.upgraded = upgraded
        self.unchanged = unchanged
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

        for manifest in manifests {
            let existing = try await packsRepo.fetch(manifest.id)

            if existing?.version == manifest.version {
                unchanged.append(manifest.id)
                continue
            }

            if existing != nil {
                let allRules = try await rulesRepo.fetchAll()
                for rule in allRules where rule.source == .pack(packId: manifest.id) {
                    try await rulesRepo.delete(rule.id)
                }
                try await packsRepo.delete(manifest.id)
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
                    enabled: true,
                    installedAt: now
                )
            )
        }

        return BootstrapSummary(installed: installed, upgraded: upgraded, unchanged: unchanged)
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
