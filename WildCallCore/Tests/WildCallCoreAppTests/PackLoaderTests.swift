import Dependencies
import Foundation
import Testing
import IssueReporting
@testable import WildCallCoreApp

@Suite struct PackLoaderTests {
    let loader = PackLoader.live
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func loadsArcepSubsetFromManifest() {
        let manifest = PackManifest(
            id: "fr.arcep",
            version: "2026-05-13",
            country: "FR",
            kind: .prefixes,
            prefixes: ["+33162*", "+33163*", "+33568*"]
        )

        withDependencies {
            $0.uuid = .incrementing
            $0.wildcardParser = .live
        } operation: {
            let rules = loader.load(manifest, now)
            #expect(rules.count == 3)
            for rule in rules {
                #expect(rule.source == .pack(packId: "fr.arcep"))
                #expect(rule.action == .block)
                #expect(rule.countryCode == "FR")
                #expect(rule.createdAt == now)
                if case .prefix(let prefix) = rule.kind {
                    // FR national length = 9, 3 fixed nat digits → 6 wildcards.
                    #expect(prefix.wildcardLength == 6)
                } else {
                    Issue.record("expected .prefix rule, got \(rule.kind)")
                }
            }
        }
    }

    @Test func skipsMalformedPatternsAndReportsThem() {
        let manifest = PackManifest(
            id: "fr.broken",
            version: "0",
            country: "FR",
            kind: .prefixes,
            prefixes: ["+33162*", "absolutely_not_a_pattern*", "+33163*"]
        )

        withKnownIssue {
            let rules = withDependencies {
                $0.uuid = .incrementing
                $0.wildcardParser = .live
            } operation: {
                loader.load(manifest, now)
            }
            #expect(rules.count == 2)
            #expect(rules.allSatisfy { $0.source == .pack(packId: "fr.broken") })
        }
    }

    @Test func bypassesPerPatternQuotaThatWouldRejectUserInput() {
        // +33162* expands to 10⁶ entries — way above the default 10⁴ per-pattern
        // quota. The loader must override the quota internally and accept it.
        let manifest = PackManifest(
            id: "fr.demo",
            version: "0",
            country: "FR",
            kind: .prefixes,
            prefixes: ["+33162*"]
        )

        let rules = withDependencies {
            $0.uuid = .incrementing
            $0.wildcardParser = .live
        } operation: {
            loader.load(manifest, now)
        }
        #expect(rules.count == 1)
        if case .prefix(let prefix) = rules.first?.kind {
            #expect(prefix.fixedDigits == "33162")
            #expect(prefix.wildcardLength == 6)
        } else {
            Issue.record("expected one prefix rule")
        }
    }
}
