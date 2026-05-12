import Foundation
import Testing
import WildCallCoreShared
@testable import WildCallCoreApp

@Suite struct BlockRuleRecordTests {
    @Test func exactRuleRoundtrip() throws {
        let rule = BlockRule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            kind: .exact(E164(33_612_345_678)!),
            source: .user,
            action: .block,
            countryCode: "FR",
            label: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let record = BlockRuleRecord.from(rule)
        let back = try record.toRule()
        #expect(back == rule)
    }

    @Test func identifyRuleWithLabelRoundtrip() throws {
        let rule = BlockRule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            kind: .exact(E164(33_899_111_222)!),
            source: .pack(packId: "fr.arcep"),
            action: .identify,
            countryCode: "FR",
            label: "Surtaxé",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let record = BlockRuleRecord.from(rule)
        let back = try record.toRule()
        #expect(back == rule)
    }

    @Test func prefixRuleRoundtrip() throws {
        let rule = BlockRule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            kind: .prefix(E164Prefix(fixedDigits: "33162999", wildcardLength: 3)),
            source: .user,
            action: .block,
            countryCode: "FR",
            label: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let record = BlockRuleRecord.from(rule)
        let back = try record.toRule()
        #expect(back == rule)
    }

    @Test func unknownKindThrows() throws {
        let record = BlockRuleRecord(
            id: UUID(),
            kindRaw: "weird",
            sourceRaw: "user",
            actionRaw: "block",
            countryCode: "FR",
            createdAt: Date()
        )
        #expect(throws: BlockRuleRecord.MappingError.self) {
            try record.toRule()
        }
    }
}
