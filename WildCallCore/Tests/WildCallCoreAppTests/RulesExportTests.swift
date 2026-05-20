import Foundation
import Testing
import CustomDump
import WildCallCoreShared
@testable import WildCallCoreApp

@Suite struct RulesExportTests {
    let exportedAt = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func buildExcludesPackRules() {
        let userRule = BlockRule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            kind: .exact(E164(33_612_345_678)!),
            source: .user,
            action: .block,
            countryCode: "FR",
            createdAt: exportedAt
        )
        let packRule = BlockRule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            kind: .prefix(.init(fixedDigits: "33162", wildcardLength: 6)),
            source: .pack(packId: "fr.arcep"),
            action: .block,
            countryCode: "FR",
            createdAt: exportedAt
        )

        let export = RulesExport.build(from: [userRule, packRule], at: exportedAt)
        #expect(export.rules.count == 1)
        #expect(export.rules.first?.id == userRule.id)
    }

    @Test func exactAndPrefixEntriesRoundtripJSON() throws {
        let userExact = BlockRule(
            kind: .exact(E164(1)!),
            source: .user, action: .block, countryCode: "FR",
            label: "Démarcheur",
            createdAt: exportedAt
        )
        let userPrefix = BlockRule(
            kind: .prefix(.init(fixedDigits: "33162999", wildcardLength: 3)),
            source: .user, action: .identify, countryCode: "FR",
            label: "Démarchage Paris",
            createdAt: exportedAt
        )

        let export = RulesExport.build(from: [userExact, userPrefix], at: exportedAt)
        let data = try export.encoded()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RulesExport.self, from: data)
        expectNoDifference(decoded, export)
    }

    @Test func emptyRulesYieldEmptyEntries() {
        let export = RulesExport.build(from: [], at: exportedAt)
        #expect(export.rules.isEmpty)
        #expect(export.format == "wildcall-rules-v1")
    }
}
