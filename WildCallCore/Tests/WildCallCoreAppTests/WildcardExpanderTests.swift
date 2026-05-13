import Foundation
import Testing
import CustomDump
@testable import WildCallCoreApp

@Suite struct WildcardExpanderTests {
    let expander = WildcardExpander.live

    @Test func expandsFrenchPatternToContiguousRange() {
        let prefix = E164Prefix(fixedDigits: "33162999", wildcardLength: 3)
        let numbers = expander.expand(prefix)
        #expect(numbers.count == 1_000)
        #expect(numbers.first == 33_162_999_000)
        #expect(numbers.last == 33_162_999_999)
    }

    @Test func expandsUsPatternAtPerPatternCap() {
        let prefix = E164Prefix(fixedDigits: "1800555", wildcardLength: 4)
        let numbers = expander.expand(prefix)
        #expect(numbers.count == 10_000)
        #expect(numbers.first == 18_005_550_000)
        #expect(numbers.last == 18_005_559_999)
    }

    @Test func expandsZeroWildcardToSingleEntry() {
        let prefix = E164Prefix(fixedDigits: "33162345678", wildcardLength: 0)
        let numbers = expander.expand(prefix)
        #expect(numbers == [33_162_345_678])
    }

    @Test func outputIsSortedAscending() {
        let prefix = E164Prefix(fixedDigits: "33162999", wildcardLength: 2)
        let numbers = expander.expand(prefix)
        #expect(numbers == numbers.sorted())
        #expect(Set(numbers).count == numbers.count) // no duplicates
    }

    @Test func countMatchesExpandCount() {
        let cases: [(String, Int)] = [
            ("33162999", 3),
            ("1800555", 4),
            ("33162345678", 0),
            ("44712345", 5),
        ]
        for (fixed, wild) in cases {
            let prefix = E164Prefix(fixedDigits: fixed, wildcardLength: wild)
            #expect(expander.count(prefix) == expander.expand(prefix).count)
        }
    }

    @Test func emptyFixedDigitsReturnsEmpty() {
        let prefix = E164Prefix(fixedDigits: "", wildcardLength: 3)
        #expect(expander.expand(prefix) == [])
    }

    @Test func snapshotFrenchPatternHeadAndTail() {
        let prefix = E164Prefix(fixedDigits: "33162999", wildcardLength: 2)
        let numbers = expander.expand(prefix)
        let head = Array(numbers.prefix(3))
        let tail = Array(numbers.suffix(3))
        expectNoDifference(head, [33_162_999_00, 33_162_999_01, 33_162_999_02])
        expectNoDifference(tail, [33_162_999_97, 33_162_999_98, 33_162_999_99])
        #expect(numbers.count == 100)
    }
}
