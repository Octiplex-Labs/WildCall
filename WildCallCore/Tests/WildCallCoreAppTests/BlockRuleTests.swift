import Foundation
import Testing
import CustomDump
@testable import WildCallCoreApp
@testable import WildCallCoreShared

@Suite struct BlockRuleTests {
    @Test func constructsExactRule() {
        let rule = BlockRule(
            kind: .exact(E164(33_612_345_678)!),
            source: .user,
            action: .block,
            countryCode: "FR"
        )
        #expect(rule.action == .block)
        #expect(rule.countryCode == "FR")
    }
}
