import Dependencies
import Foundation
import Testing
@testable import WildCallCoreApp

@Suite struct WildcardQuotasTests {
    @Test func defaultValuesAreStable() {
        let quotas = WildcardQuotas.default
        #expect(quotas.perPattern == 10_000)
        #expect(quotas.totalUser == 5_000_000)
        #expect(quotas.minFixedDigits == 6)
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
