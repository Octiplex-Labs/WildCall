import Dependencies
import Foundation

/// Limits on user-entered wildcard patterns.
///
/// Since the store is range-based, the app never pays for wide patterns :
/// the only cost is the time iOS needs to ingest the numbers in the Call
/// Directory extension (roughly linear in the total count). The quotas
/// therefore express an ingestion budget, not a memory budget.
public struct WildcardQuotas: Sendable, Equatable {
    /// Maximum numbers a single pattern may cover. 10^6 lets a French user
    /// type `0123*` (every number after "01 23"), which is the widest range
    /// that still makes sense for a manual rule.
    public let perPattern: Int
    /// Maximum numbers across all user patterns combined.
    public let totalUser: Int
    /// Minimum national-significant digits before the `*` (after stripping
    /// the trunk prefix, so `01*` in France is 1 digit and gets rejected by
    /// `perPattern` before this even matters).
    public let minFixedDigits: Int
    /// Hard ceiling of one Call Directory extension. Measured on iPhone 17
    /// Pro / iOS 26.6.1 (2026-09-01): 1 999 999 entries load in 9 s,
    /// 2 000 000 fail with `maximumEntriesExceeded`. Packs and user rules
    /// together must stay under it, or iOS rejects the whole list.
    public let maxExtensionEntries: Int

    public init(
        perPattern: Int,
        totalUser: Int,
        minFixedDigits: Int,
        maxExtensionEntries: Int = WildcardQuotas.measuredExtensionCeiling
    ) {
        self.perPattern = perPattern
        self.totalUser = totalUser
        self.minFixedDigits = minFixedDigits
        self.maxExtensionEntries = maxExtensionEntries
    }

    public static let measuredExtensionCeiling = 1_999_999

    public static let `default` = WildcardQuotas(
        perPattern: 1_000_000,
        totalUser: 1_999_999,
        minFixedDigits: 2
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
