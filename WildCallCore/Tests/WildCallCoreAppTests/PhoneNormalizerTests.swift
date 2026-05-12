import Foundation
import Testing
import WildCallCoreShared
@testable import WildCallCoreApp

@Suite struct PhoneNormalizerTests {
    @Test func normalizesFrenchMobile() throws {
        let normalizer = PhoneNormalizer.live
        let e164 = try normalizer.normalize("06 12 34 56 78", "FR")
        #expect(e164.value == 33_612_345_678)
    }

    @Test func normalizesWithInternationalPrefix() throws {
        let normalizer = PhoneNormalizer.live
        let e164 = try normalizer.normalize("+33 6 12 34 56 78", "FR")
        #expect(e164.value == 33_612_345_678)
    }

    @Test func normalizesAmericanNumber() throws {
        let normalizer = PhoneNormalizer.live
        let e164 = try normalizer.normalize("(212) 555-0100", "US")
        #expect(e164.value == 1_212_555_0100)
    }

    @Test func rejectsObviousJunk() {
        let normalizer = PhoneNormalizer.live
        #expect(throws: (any Error).self) {
            try normalizer.normalize("not a number", "FR")
        }
    }

    @Test func validatesWithoutThrowing() {
        let normalizer = PhoneNormalizer.live
        #expect(normalizer.validate("06 12 34 56 78", "FR"))
        #expect(!normalizer.validate("abc", "FR"))
    }

    @Test func formatRoundtrip() throws {
        let normalizer = PhoneNormalizer.live
        let e164 = try normalizer.normalize("06 12 34 56 78", "FR")
        #expect(normalizer.format(e164) == "+33612345678")
    }
}
