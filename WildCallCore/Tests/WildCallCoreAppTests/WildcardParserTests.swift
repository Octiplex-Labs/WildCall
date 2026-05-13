import Dependencies
import Foundation
import Testing
import CustomDump
@testable import WildCallCoreApp

@Suite struct WildcardParserTests {
    let parser = WildcardParser.live

    @Test func parsesFrenchPattern() {
        let result = parser.parse("+33162999*", "FR")
        switch result {
        case .success(let prefix):
            #expect(prefix.fixedDigits == "33162999")
            #expect(prefix.wildcardLength == 3)
        case .failure(let error):
            Issue.record("expected success, got \(error)")
        }
    }

    @Test func parsesUsPatternHittingPerPatternCap() {
        let result = parser.parse("+1800555*", "US")
        switch result {
        case .success(let prefix):
            #expect(prefix.fixedDigits == "1800555")
            #expect(prefix.wildcardLength == 4)
        case .failure(let error):
            Issue.record("expected success, got \(error)")
        }
    }

    @Test func parsesPatternWithEmbeddedSpaces() {
        let resultA = parser.parse("+33 1 62 999*", "FR")
        let resultB = parser.parse("+33162999*", "FR")
        expectNoDifference(resultA, resultB)
    }

    @Test func parsesNationalInputUsingDefaultRegion() {
        let result = parser.parse("162999*", "FR")
        switch result {
        case .success(let prefix):
            #expect(prefix.fixedDigits == "33162999")
            #expect(prefix.wildcardLength == 3)
        case .failure(let error):
            Issue.record("expected success, got \(error)")
        }
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
        #expect(parser.parse("+33162*", "FR") == .failure(.fixedTooShort(minimum: 6)))
        #expect(parser.parse("+3316*", "FR") == .failure(.fixedTooShort(minimum: 6)))
        #expect(parser.parse("+33*", "FR") == .failure(.fixedTooShort(minimum: 6)))
        #expect(parser.parse("16299*", "FR") == .failure(.fixedTooShort(minimum: 6)))
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
        // 9 national digits in FR = exactly max length, wildcardLength = 0,
        // expanded = 1 entry. Edge but valid.
        let result = parser.parse("+33162345678*", "FR")
        switch result {
        case .success(let prefix):
            #expect(prefix.fixedDigits == "33162345678")
            #expect(prefix.wildcardLength == 0)
        case .failure(let error):
            Issue.record("expected success, got \(error)")
        }
    }

    @Test func pow10Helper() {
        #expect(WildcardParser.pow10(0) == 1)
        #expect(WildcardParser.pow10(1) == 10)
        #expect(WildcardParser.pow10(4) == 10_000)
        #expect(WildcardParser.pow10(-1) == 0)
    }
}
