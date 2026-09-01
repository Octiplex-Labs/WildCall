import Foundation
import WildCallCoreShared

/// Read model for the Filtres tab : user rules stay individual, pack rules
/// collapse into one row per pack, and inside a pack into one row per
/// number root (the first digits shared by every pattern, e.g. "01 62").
public struct PackGroup: Equatable, Sendable, Identifiable {
    public let pack: InstalledPack
    public let ruleCount: Int
    public let numberCount: Int
    public let roots: [RootGroup]

    public var id: String { pack.id }

    public init(pack: InstalledPack, ruleCount: Int, numberCount: Int, roots: [RootGroup]) {
        self.pack = pack
        self.ruleCount = ruleCount
        self.numberCount = numberCount
        self.roots = roots
    }
}

public struct RootGroup: Equatable, Sendable, Identifiable {
    /// Country code + leading national digits, e.g. "33162" for "01 62".
    public let root: String
    public let countryCode: String
    public let rules: [BlockRule]
    public let numberCount: Int

    public var id: String { root }

    public init(root: String, countryCode: String, rules: [BlockRule], numberCount: Int) {
        self.root = root
        self.countryCode = countryCode
        self.rules = rules
        self.numberCount = numberCount
    }

    /// True when the root itself is the only rule : a single wide pattern
    /// (`+33162*`) needs no detail list.
    public var isSinglePattern: Bool { rules.count == 1 }
}

public enum RuleGrouping {
    /// Number of national digits (after the country code) that define a
    /// root. Four for France ("0162" → "162" + …). Roots are computed on
    /// the E.164 digits so `33162…` groups under `33162`.
    public static let rootNationalDigits = 3

    public static func group(
        rules: [BlockRule],
        packs: [InstalledPack],
        count: (E164Prefix) -> Int
    ) -> (user: [BlockRule], packs: [PackGroup]) {
        var user: [BlockRule] = []
        var byPack: [String: [BlockRule]] = [:]
        for rule in rules {
            switch rule.source {
            case .user: user.append(rule)
            case .pack(let id): byPack[id, default: []].append(rule)
            }
        }

        let groups = packs.map { pack -> PackGroup in
            let packRules = byPack[pack.id] ?? []
            let roots = Self.roots(of: packRules, count: count)
            return PackGroup(
                pack: pack,
                ruleCount: packRules.count,
                numberCount: roots.reduce(0) { $0 + $1.numberCount },
                roots: roots
            )
        }
        return (user, groups)
    }

    static func roots(of rules: [BlockRule], count: (E164Prefix) -> Int) -> [RootGroup] {
        var buckets: [String: (country: String, rules: [BlockRule], numbers: Int)] = [:]
        for rule in rules {
            let (digits, numbers): (String, Int)
            switch rule.kind {
            case .exact(let e164): (digits, numbers) = (String(e164.value), 1)
            case .prefix(let prefix): (digits, numbers) = (prefix.fixedDigits, count(prefix))
            }
            let root = Self.root(of: digits, countryCode: rule.countryCode)
            var bucket = buckets[root] ?? (rule.countryCode, [], 0)
            bucket.rules.append(rule)
            bucket.numbers += numbers
            buckets[root] = bucket
        }
        return buckets
            .map { root, bucket in
                RootGroup(
                    root: root,
                    countryCode: bucket.country,
                    rules: bucket.rules.sorted { Self.sortKey($0) < Self.sortKey($1) },
                    numberCount: bucket.numbers
                )
            }
            .sorted { $0.root < $1.root }
    }

    /// Country calling code length is not stored on the rule; derive it
    /// from the E.164 digits by trying the known 1-3 digit codes of the
    /// rule's country. Falls back to the first 2 digits.
    static func root(of digits: String, countryCode: String) -> String {
        let callingCodeLength = Self.callingCodeLength(for: countryCode)
        let end = min(digits.count, callingCodeLength + rootNationalDigits)
        return String(digits.prefix(end))
    }

    static func callingCodeLength(for countryCode: String) -> Int {
        switch countryCode {
        case "US", "CA": return 1
        case "FR", "BE", "CH", "GB", "DE", "ES", "IT", "PT", "NL", "LU", "AT", "SE", "NO", "DK", "PL", "IE": return 2
        default: return 3
        }
    }

    static func sortKey(_ rule: BlockRule) -> String {
        switch rule.kind {
        case .exact(let e164): return String(e164.value)
        case .prefix(let prefix): return prefix.fixedDigits
        }
    }
}
