import Foundation
import Testing
import WildCallCoreShared
@testable import WildCallCoreApp

@Suite struct RuleGroupingTests {
    let arcep = InstalledPack(id: "fr.arcep", version: "v1", country: "FR", enabled: true, installedAt: Date(), title: "Démarchage (ARCEP)")

    func packRule(_ fixed: String, wild: Int) -> BlockRule {
        BlockRule(kind: .prefix(.init(fixedDigits: fixed, wildcardLength: wild)), source: .pack(packId: "fr.arcep"), action: .block, countryCode: "FR")
    }

    @Test func separatesUserRulesFromPackGroups() {
        let user = BlockRule(kind: .exact(E164(33_612_345_678)!), source: .user, action: .block, countryCode: "FR")
        let rules = [user, packRule("33162040", wild: 3), packRule("3316205", wild: 4), packRule("33427865", wild: 3)]
        let grouped = RuleGrouping.group(rules: rules, packs: [arcep], count: WildcardExpander.live.count)

        #expect(grouped.user == [user])
        #expect(grouped.packs.count == 1)
        let group = grouped.packs[0]
        #expect(group.pack.id == "fr.arcep")
        #expect(group.ruleCount == 3)
        #expect(group.numberCount == 1_000 + 10_000 + 1_000)
        #expect(group.roots.map(\.root) == ["33162", "33427"])
        #expect(group.roots[0].rules.count == 2)
        #expect(group.roots[0].numberCount == 11_000)
        #expect(group.roots[1].isSinglePattern)
    }

    @Test func packsWithoutRulesStillAppear() {
        let grouped = RuleGrouping.group(rules: [], packs: [arcep], count: WildcardExpander.live.count)
        #expect(grouped.packs.count == 1)
        #expect(grouped.packs[0].roots.isEmpty)
        #expect(grouped.packs[0].numberCount == 0)
    }

    @Test func rootUsesCallingCodeLengthOfTheCountry() {
        #expect(RuleGrouping.root(of: "33162040", countryCode: "FR") == "33162")
        #expect(RuleGrouping.root(of: "1800555", countryCode: "US") == "1800")
        #expect(RuleGrouping.root(of: "3316", countryCode: "FR") == "3316")
    }

    @Test func rulesInsideARootAreSortedByDigits() {
        let rules = [packRule("33162090", wild: 3), packRule("33162040", wild: 3), packRule("3316205", wild: 4)]
        let roots = RuleGrouping.roots(of: rules, count: WildcardExpander.live.count)
        #expect(roots.count == 1)
        #expect(roots[0].rules.map { RuleGrouping.sortKey($0) } == ["33162040", "3316205", "33162090"])
    }
}
