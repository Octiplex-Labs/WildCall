import Dependencies
import Foundation

public struct WildcardExpander: Sendable {
    public var expand: @Sendable (_ prefix: E164Prefix) -> [Int64]
    public var count: @Sendable (_ prefix: E164Prefix) -> Int

    public init(
        expand: @escaping @Sendable (E164Prefix) -> [Int64],
        count: @escaping @Sendable (E164Prefix) -> Int
    ) {
        self.expand = expand
        self.count = count
    }
}

extension WildcardExpander {
    public static let live = WildcardExpander(
        expand: { prefix in
            guard let base = Int64(prefix.fixedDigits) else { return [] }
            let count = Self.pow10(prefix.wildcardLength)
            let multiplier = Int64(count)
            let start = base * multiplier
            return Array(start..<(start + multiplier))
        },
        count: { prefix in
            Self.pow10(prefix.wildcardLength)
        }
    )

    static func pow10(_ exponent: Int) -> Int {
        guard exponent >= 0 else { return 0 }
        return (0..<exponent).reduce(1) { acc, _ in acc * 10 }
    }
}

extension WildcardExpander: DependencyKey {
    public static let liveValue: WildcardExpander = .live
    public static let testValue: WildcardExpander = WildcardExpander(
        expand: { _ in unimplemented("WildcardExpander.expand", placeholder: []) },
        count: { _ in unimplemented("WildcardExpander.count", placeholder: 0) }
    )
}

extension DependencyValues {
    public var wildcardExpander: WildcardExpander {
        get { self[WildcardExpander.self] }
        set { self[WildcardExpander.self] = newValue }
    }
}
