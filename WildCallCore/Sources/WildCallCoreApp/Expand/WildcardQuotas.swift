import Dependencies
import Foundation

public struct WildcardQuotas: Sendable, Equatable {
    public let perPattern: Int
    public let totalUser: Int
    public let minFixedDigits: Int

    public init(perPattern: Int, totalUser: Int, minFixedDigits: Int) {
        self.perPattern = perPattern
        self.totalUser = totalUser
        self.minFixedDigits = minFixedDigits
    }

    public static let `default` = WildcardQuotas(
        perPattern: 10_000,
        totalUser: 5_000_000,
        minFixedDigits: 6
    )
}

extension WildcardQuotas: DependencyKey {
    public static let liveValue: WildcardQuotas = .default
    public static let testValue: WildcardQuotas = .default
}

extension DependencyValues {
    public var wildcardQuotas: WildcardQuotas {
        get { self[WildcardQuotas.self] }
        set { self[WildcardQuotas.self] = newValue }
    }
}
