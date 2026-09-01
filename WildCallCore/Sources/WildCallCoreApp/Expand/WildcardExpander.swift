import Dependencies
import Foundation
import WildCallCoreShared

/// Turns a prefix into the contiguous range it covers. `+33162*` with 6
/// wildcard digits is `[33162000000, 33163000000)`. Nothing is materialised :
/// the range itself is what gets written to the shared store.
public struct WildcardExpander: Sendable {
    public var range: @Sendable (_ prefix: E164Prefix) -> NumberRange?
    public var count: @Sendable (_ prefix: E164Prefix) -> Int

    public init(
        range: @escaping @Sendable (E164Prefix) -> NumberRange?,
        count: @escaping @Sendable (E164Prefix) -> Int
    ) {
        self.range = range
        self.count = count
    }
}

extension WildcardExpander {
    public static let live = WildcardExpander(
        range: { prefix in
            guard let base = Int64(prefix.fixedDigits), prefix.wildcardLength >= 0 else { return nil }
            let multiplier = Int64(Self.pow10(prefix.wildcardLength))
            let (start, overflow) = base.multipliedReportingOverflow(by: multiplier)
            guard !overflow else { return nil }
            return NumberRange(start: start, count: multiplier)
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
        range: { _ in unimplemented("WildcardExpander.range", placeholder: nil) },
        count: { _ in unimplemented("WildcardExpander.count", placeholder: 0) }
    )
}

extension DependencyValues {
    public var wildcardExpander: WildcardExpander {
        get { self[WildcardExpander.self] }
        set { self[WildcardExpander.self] = newValue }
    }
}
