import Dependencies
import Foundation
import SwiftData
import Testing
@testable import WildCallCoreApp

@Suite struct DefaultPackPolicyTests {
    static let repoRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()  // WildCallCoreAppTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // WildCallCore
        .deletingLastPathComponent()

    static let now = Date(timeIntervalSince1970: 1_700_000_000)

    static func embeddedManifests() throws -> [PackManifest] {
        let folder = repoRoot.appending(path: "Packs")
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".source.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map(PackManifest.load(from:))
    }

    func manifest(country: String, enabledByDefault: Bool? = nil) -> PackManifest {
        PackManifest(
            id: "\(country.lowercased()).test", version: "2026-11-11", country: country,
            kind: .prefixes, enabledByDefault: enabledByDefault, prefixes: []
        )
    }

    @Test func onlyTheDeviceCountryStartsEnabled() {
        #expect(DefaultPackPolicy.enablesOnFreshInstall(manifest(country: "FR"), region: "FR"))
        #expect(!DefaultPackPolicy.enablesOnFreshInstall(manifest(country: "DE"), region: "FR"))
        #expect(!DefaultPackPolicy.enablesOnFreshInstall(manifest(country: "US"), region: "FR"))
        #expect(DefaultPackPolicy.enablesOnFreshInstall(manifest(country: "US"), region: "us"))
    }

    @Test func overseasRegionsUseTheFrenchPacks() {
        for region in ["GP", "MQ", "GF", "RE", "YT", "BL", "MF", "PM"] {
            #expect(DefaultPackPolicy.enablesOnFreshInstall(manifest(country: "FR"), region: region))
        }
    }

    @Test func unknownRegionEnablesNothing() {
        #expect(!DefaultPackPolicy.enablesOnFreshInstall(manifest(country: "FR"), region: nil))
        #expect(!DefaultPackPolicy.enablesOnFreshInstall(manifest(country: "FR"), region: ""))
        #expect(!DefaultPackPolicy.enablesOnFreshInstall(manifest(country: "FR"), region: "BE"))
    }

    @Test func aManifestShippedDisabledStaysOffAtHome() {
        #expect(!DefaultPackPolicy.enablesOnFreshInstall(manifest(country: "FR", enabledByDefault: false), region: "FR"))
    }

    @Test func bootstrapEnablesOnlyTheHomeCountry() async throws {
        let container = try ModelContainer(
            for: BlockRuleRecord.self, PackRecord.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
        let packsRepo = PacksRepository.live(container: container)
        let manifests = [
            PackManifest(id: "fr.arcep", version: "2026-11-11", country: "FR", kind: .prefixes, prefixes: ["+33162*"]),
            PackManifest(id: "es.cnmc", version: "2026-11-11", country: "ES", kind: .prefixes, prefixes: ["+34400*"]),
        ]
        _ = try await withDependencies {
            $0.rulesRepository = .live(container: container)
            $0.packsRepository = packsRepo
            $0.packLoader = .live
            $0.wildcardParser = .live
            $0.date = .constant(Self.now)
            $0.uuid = .incrementing
            $0.deviceRegion = DeviceRegion { "ES" }
        } operation: {
            try await PackBootstrap.live.run(manifests)
        }
        #expect(try await packsRepo.fetch("fr.arcep")?.enabled == false)
        #expect(try await packsRepo.fetch("es.cnmc")?.enabled == true)
    }

    /// The point of the policy : whatever the country, the packs enabled on
    /// a fresh install fit in the extensions.
    @Test func everyCountryFitsInTheExtensions() throws {
        let manifests = try Self.embeddedManifests()
        #expect(!manifests.isEmpty)
        let capacity = WildcardQuotas.default.totalCapacity

        var numbersByPack: [String: Int] = [:]
        for manifest in manifests {
            let rules = withDependencies {
                $0.uuid = .incrementing
                $0.wildcardParser = .live
            } operation: {
                PackLoader.live.load(manifest, Self.now)
            }
            #expect(!rules.isEmpty, "\(manifest.id) loads no rule")
            numbersByPack[manifest.id] = rules.reduce(0) { total, rule in
                switch rule.kind {
                case .exact: total + 1
                case .prefix(let prefix): total + Int(pow(10.0, Double(prefix.wildcardLength)))
                }
            }
        }

        for region in Set(manifests.map(\.country)) {
            let enabled = manifests.filter { DefaultPackPolicy.enablesOnFreshInstall($0, region: region) }
            #expect(!enabled.isEmpty, "no default pack for \(region)")
            let total = enabled.reduce(0) { $0 + (numbersByPack[$1.id] ?? 0) }
            #expect(total <= capacity, "\(region) starts with \(total) numbers, capacity is \(capacity)")
        }

        // Enabling everything at once is what the policy prevents.
        let everything = numbersByPack.values.reduce(0, +)
        #expect(everything > capacity)
    }

    @Test func embeddedPacksMatchTheirSigningMirror() throws {
        for manifest in try Self.embeddedManifests() {
            let mirror = Self.repoRoot.appending(path: "dist/packs/source/\(manifest.id).source.json")
            #expect(try PackManifest.load(from: mirror) == manifest, "\(manifest.id) differs from dist/packs/source")
        }
    }
}
