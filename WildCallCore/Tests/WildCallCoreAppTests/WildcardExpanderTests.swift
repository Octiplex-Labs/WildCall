import Foundation
import Testing
import WildCallCoreShared
@testable import WildCallCoreApp

@Suite struct WildcardExpanderTests {
    let expander = WildcardExpander.live

    @Test func frenchPatternBecomesContiguousRange() {
        let prefix = E164Prefix(fixedDigits: "33162999", wildcardLength: 3)
        #expect(expander.range(prefix) == NumberRange(start: 33_162_999_000, count: 1_000))
        #expect(expander.count(prefix) == 1_000)
    }

    @Test func widePatternIsStillOneRange() {
        let prefix = E164Prefix(fixedDigits: "33162", wildcardLength: 6)
        let range = expander.range(prefix)
        #expect(range == NumberRange(start: 33_162_000_000, count: 1_000_000))
        #expect(range?.last == 33_162_999_999)
    }

    @Test func usPatternAtFourWildcards() {
        let prefix = E164Prefix(fixedDigits: "1800555", wildcardLength: 4)
        #expect(expander.range(prefix) == NumberRange(start: 18_005_550_000, count: 10_000))
    }

    @Test func zeroWildcardIsSingleNumber() {
        let prefix = E164Prefix(fixedDigits: "33162345678", wildcardLength: 0)
        #expect(expander.range(prefix) == .single(33_162_345_678))
        #expect(expander.count(prefix) == 1)
    }

    @Test func countMatchesRangeCount() {
        let cases: [(String, Int)] = [("33162999", 3), ("1800555", 4), ("33162345678", 0), ("44712345", 5)]
        for (fixed, wild) in cases {
            let prefix = E164Prefix(fixedDigits: fixed, wildcardLength: wild)
            #expect(Int64(expander.count(prefix)) == expander.range(prefix)?.count)
        }
    }

    @Test func emptyFixedDigitsReturnsNil() {
        #expect(expander.range(E164Prefix(fixedDigits: "", wildcardLength: 3)) == nil)
    }

    @Test func overflowReturnsNil() {
        #expect(expander.range(E164Prefix(fixedDigits: "999999999999999", wildcardLength: 10)) == nil)
    }
}
