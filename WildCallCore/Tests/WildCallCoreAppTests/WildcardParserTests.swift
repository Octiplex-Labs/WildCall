import Dependencies
import Foundation
import Testing
import CustomDump
@testable import WildCallCoreApp

@Suite struct WildcardParserTests {
    let parser = WildcardParser.live

    @Test func parsesFrenchPattern() {
        let result = parser.parse("+33162999*", "FR")
        #expect(result == .success(E164Prefix(fixedDigits: "33162999", wildcardLength: 3)))
    }

    @Test func parsesWideFrenchPatternRequestedByUsers() {
        // "0123*" = every number after "01 23" : 10^6 numbers, one range.
        #expect(parser.parse("0123*", "FR") == .success(E164Prefix(fixedDigits: "33123", wildcardLength: 6)))
        #expect(parser.parse("01 23*", "FR") == .success(E164Prefix(fixedDigits: "33123", wildcardLength: 6)))
        #expect(parser.parse("+33123*", "FR") == .success(E164Prefix(fixedDigits: "33123", wildcardLength: 6)))
    }

    @Test func stripsFrenchTrunkPrefixOnNationalInput() {
        // Regression : "0162*" used to become 330162xxxxx (never matches).
        #expect(parser.parse("0162999*", "FR") == .success(E164Prefix(fixedDigits: "33162999", wildcardLength: 3)))
        #expect(parser.parse("0162999*", "FR") == parser.parse("+33162999*", "FR"))
    }

    @Test func stripsNanpTrunkPrefixOnNationalInput() {
        #expect(parser.parse("1800555*", "US") == parser.parse("+1800555*", "US"))
        #expect(parser.parse("800555*", "US") == .success(E164Prefix(fixedDigits: "1800555", wildcardLength: 4)))
    }

    @Test func doesNotStripWhenRegionHasNoTrunkPrefix() {
        // Italian numbers start with 0 and have no trunk prefix : keep it.
        let result = withDependencies {
            $0.wildcardQuotas = WildcardQuotas(perPattern: .max, totalUser: .max, minFixedDigits: 1)
        } operation: {
            parser.parse("0612*", "IT")
        }
        if case .success(let prefix) = result {
            #expect(prefix.fixedDigits == "390612")
        } else {
            Issue.record("expected success, got \(result)")
        }
    }

    @Test func parsesUsPattern() {
        let result = parser.parse("+1800555*", "US")
        #expect(result == .success(E164Prefix(fixedDigits: "1800555", wildcardLength: 4)))
    }

    @Test func parsesPatternWithEmbeddedSpaces() {
        expectNoDifference(parser.parse("+33 1 62 999*", "FR"), parser.parse("+33162999*", "FR"))
    }

    @Test func parsesNationalInputUsingDefaultRegion() {
        #expect(parser.parse("162999*", "FR") == .success(E164Prefix(fixedDigits: "33162999", wildcardLength: 3)))
    }

    @Test func rejectsEmptyInput() {
        #expect(parser.parse("", "FR") == .failure(.empty))
        #expect(parser.parse("   ", "FR") == .failure(.empty))
    }

    @Test func rejectsMissingWildcard() {
        #expect(parser.parse("+33162999", "FR") == .failure(.missingWildcard))
    }

    @Test func rejectsNonTrailingWildcard() {
        #expect(parser.parse("+33*162999", "FR") == .failure(.wildcardNotTrailing))
        #expect(parser.parse("*33162999", "FR") == .failure(.wildcardNotTrailing))
        #expect(parser.parse("+33162999**", "FR") == .failure(.wildcardNotTrailing))
        #expect(parser.parse("+33*1629*99*", "FR") == .failure(.wildcardNotTrailing))
        #expect(parser.parse("*", "FR") == .failure(.wildcardNotTrailing))
    }

    @Test func rejectsFixedTooShort() {
        #expect(parser.parse("+331*", "FR") == .failure(.fixedTooShort(minimum: 2)))
        #expect(parser.parse("+33*", "FR") == .failure(.fixedTooShort(minimum: 2)))
        #expect(parser.parse("0*", "FR") == .failure(.fixedTooShort(minimum: 2)))
        #expect(parser.parse("01*", "FR") == .failure(.fixedTooShort(minimum: 2)))
    }

    @Test func rejectsPatternsWiderThanOneMillion() {
        // "012*" would be 10^7 numbers : refused with the actual count so the
        // UI can explain.
        #expect(parser.parse("012*", "FR") == .failure(.exceedsPerPatternQuota(expanded: 10_000_000, limit: 1_000_000)))
        #expect(parser.parse("+3312*", "FR") == .failure(.exceedsPerPatternQuota(expanded: 10_000_000, limit: 1_000_000)))
    }

    @Test func rejectsFixedTooLong() {
        // FR max national = 9. Eleven national digits exceed it.
        #expect(parser.parse("+3312345678901*", "FR") == .failure(.fixedTooLong(maximum: 9)))
    }

    @Test func rejectsUnparseable() {
        #expect(parser.parse("azerty*", "FR") == .failure(.unparseable))
        #expect(parser.parse("+abc*", "FR") == .failure(.unparseable))
        #expect(parser.parse("+0099999*", "FR") == .failure(.unparseable))
    }

    @Test func rejectsExceedsPerPatternQuotaUnderTightenedQuota() {
        let tight = WildcardQuotas(perPattern: 100, totalUser: 1_000_000, minFixedDigits: 4)
        withDependencies {
            $0.wildcardQuotas = tight
        } operation: {
            // 4 fixed nat digits + 5 wild = 10⁵ entries > 100.
            let result = parser.parse("+331629*", "FR")
            #expect(result == .failure(.exceedsPerPatternQuota(expanded: 100_000, limit: 100)))
        }
    }

    @Test func acceptsZeroWildcardWhenFixedHitsMaxLength() {
        let result = parser.parse("+33162345678*", "FR")
        #expect(result == .success(E164Prefix(fixedDigits: "33162345678", wildcardLength: 0)))
    }

    @Test func stripTrunkPrefixHelper() {
        #expect(WildcardParser.stripTrunkPrefix("0162", trunkPrefix: "0") == "162")
        #expect(WildcardParser.stripTrunkPrefix("162", trunkPrefix: "0") == "162")
        #expect(WildcardParser.stripTrunkPrefix("0162", trunkPrefix: nil) == "0162")
        #expect(WildcardParser.stripTrunkPrefix("0162", trunkPrefix: "") == "0162")
    }

    @Test func pow10Helper() {
        #expect(WildcardParser.pow10(0) == 1)
        #expect(WildcardParser.pow10(1) == 10)
        #expect(WildcardParser.pow10(4) == 10_000)
        #expect(WildcardParser.pow10(-1) == 0)
    }
}
