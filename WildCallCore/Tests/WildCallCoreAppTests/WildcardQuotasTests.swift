import Dependencies
import Foundation
import Testing
@testable import WildCallCoreApp

@Suite struct WildcardQuotasTests {
    @Test func defaultValuesAreStable() {
        let quotas = WildcardQuotas.default
        #expect(quotas.perPattern == 1_000_000)
        #expect(quotas.totalUser == 1_999_999)
        #expect(quotas.minFixedDigits == 2)
        #expect(quotas.maxExtensionEntries == 1_999_999)
    }

    @Test func liveAndTestValuesEqualDefault() {
        #expect(WildcardQuotas.liveValue == .default)
        #expect(WildcardQuotas.testValue == .default)
    }

    @Test func dependencyOverrideTakesEffect() {
        let override = WildcardQuotas(perPattern: 5, totalUser: 50, minFixedDigits: 3)
        withDependencies {
            $0.wildcardQuotas = override
        } operation: {
            @Dependency(\.wildcardQuotas) var quotas
            #expect(quotas == override)
        }
    }
}
