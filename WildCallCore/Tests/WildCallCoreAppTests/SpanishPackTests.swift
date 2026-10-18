import Dependencies
import Foundation
import SwiftData
import Testing
@testable import WildCallCoreApp

/// Checks the es.cnmc pack exactly as it ships : the embedded source in
/// `Packs/`, its signing mirror in `dist/packs/source/` and its index entry.
@Suite struct SpanishPackTests {
    static let repoRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()  // WildCallCoreAppTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // WildCallCore
        .deletingLastPathComponent()

    static let embeddedURL = repoRoot.appending(path: "Packs/prefixes-ES.source.json")
    static let distURL = repoRoot.appending(path: "dist/packs/source/es.cnmc.source.json")
    static let indexURL = repoRoot.appending(path: "dist/packs/index.json")

    let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func embeddedManifestDescribesTheWhole400Range() throws {
        let manifest = try PackManifest.load(from: Self.embeddedURL)
        #expect(manifest.id == "es.cnmc")
        #expect(manifest.country == "ES")
        #expect(manifest.kind == .prefixes)
        #expect(manifest.enabledByDefault == false)
        #expect(manifest.prefixes == ["+34400*"])
        #expect(manifest.supersedes == nil)
        #expect(manifest.publisherKey == nil)
        #expect(manifest.title?.contains("Espagne") == true)
        for text in [manifest.title, manifest.notes, manifest.license].compactMap({ $0 }) {
            #expect(!text.contains("—"), "no em-dash in pack copy")
        }
    }

    @Test func distMirrorIsByteIdenticalToEmbeddedSource() throws {
        // The signed .wildcallpack covers the dist bytes : a drift would mean
        // the remote pack differs from the one in the app.
        #expect(try Data(contentsOf: Self.distURL) == Data(contentsOf: Self.embeddedURL))
    }

    @Test func indexListsThePackAtTheEmbeddedVersion() throws {
        let manifest = try PackManifest.load(from: Self.embeddedURL)
        let index = try JSONDecoder().decode(PackIndex.self, from: Data(contentsOf: Self.indexURL))
        let entry = try #require(index.packs.first { $0.id == "es.cnmc" })
        #expect(entry.version == manifest.version)
        #expect(entry.country == "ES")
        #expect(entry.kind == .prefixes)
        #expect(entry.url.lastPathComponent == "es.cnmc-\(manifest.version).wildcallpack")
    }

    @Test func loadsAsOneMillionNumbersUnderTheExtensionCeiling() throws {
        let manifest = try PackManifest.load(from: Self.embeddedURL)
        let rules = withDependencies {
            $0.uuid = .incrementing
            $0.wildcardParser = .live
        } operation: {
            PackLoader.live.load(manifest, now)
        }
        #expect(rules.count == 1)
        let rule = try #require(rules.first)
        #expect(rule.source == .pack(packId: "es.cnmc"))
        #expect(rule.action == .block)
        #expect(rule.countryCode == "ES")
        guard case .prefix(let prefix) = rule.kind else {
            Issue.record("expected .prefix rule, got \(rule.kind)")
            return
        }
        // ES national length = 9, "400" fixed → 6 wildcards : 400 000 000 … 400 999 999.
        #expect(prefix.fixedDigits == "34400")
        #expect(prefix.wildcardLength == 6)
        let numbers = Int(pow(10.0, Double(prefix.wildcardLength)))
        #expect(numbers == 1_000_000)
        #expect(numbers <= WildcardQuotas.measuredExtensionCeiling)
    }

    @Test func groupsUnderASingleSpanishRoot() throws {
        let manifest = try PackManifest.load(from: Self.embeddedURL)
        let rules = withDependencies {
            $0.uuid = .incrementing
            $0.wildcardParser = .live
        } operation: {
            PackLoader.live.load(manifest, now)
        }
        let pack = InstalledPack(
            id: manifest.id, version: manifest.version, country: manifest.country,
            enabled: false, installedAt: now, title: manifest.title
        )
        let grouped = RuleGrouping.group(rules: rules, packs: [pack]) { prefix in
            Int(pow(10.0, Double(prefix.wildcardLength)))
        }
        #expect(grouped.user.isEmpty)
        let group = try #require(grouped.packs.first)
        #expect(group.numberCount == 1_000_000)
        #expect(group.roots.map(\.root) == ["34400"])
    }

    @Test func bootstrapInstallsItDisabled() async throws {
        let container = try ModelContainer(
            for: BlockRuleRecord.self, PackRecord.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
        let rulesRepo = RulesRepository.live(container: container)
        let packsRepo = PacksRepository.live(container: container)
        let manifest = try PackManifest.load(from: Self.embeddedURL)

        let summary = try await withDependencies {
            $0.rulesRepository = rulesRepo
            $0.packsRepository = packsRepo
            $0.packLoader = .live
            $0.wildcardParser = .live
            $0.date = .constant(now)
            $0.uuid = .incrementing
        } operation: {
            try await PackBootstrap.live.run([manifest])
        }
        #expect(summary.installed == ["es.cnmc"])
        let pack = try #require(try await packsRepo.fetch("es.cnmc"))
        #expect(pack.enabled == false)
        #expect(pack.title == manifest.title)
        #expect(try await rulesRepo.fetchAll().count == 1)
    }
}
