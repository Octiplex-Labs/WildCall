import Foundation
import WildCallCoreShared

/// Versioned wire format for user-rule backup/restore. Pack-sourced rules
/// are excluded — those are recreated by syncing the catalogue, not by
/// importing a backup.
public struct RulesExport: Codable, Equatable, Sendable {
    public let format: String  // "wildcall-rules-v1"
    public let exportedAt: Date
    public let rules: [Entry]

    public init(format: String, exportedAt: Date, rules: [Entry]) {
        self.format = format
        self.exportedAt = exportedAt
        self.rules = rules
    }

    public struct Entry: Codable, Equatable, Sendable {
        public let id: UUID
        public let kind: String              // "exact" | "prefix"
        public let e164: Int64?              // for kind=exact
        public let fixedDigits: String?      // for kind=prefix
        public let wildcardLength: Int?      // for kind=prefix
        public let action: String            // "block" | "identify"
        public let country: String
        public let label: String?
        public let createdAt: Date

        public init(rule: BlockRule) {
            self.id = rule.id
            self.action = rule.action.rawValue
            self.country = rule.countryCode
            self.label = rule.label
            self.createdAt = rule.createdAt
            switch rule.kind {
            case .exact(let e164):
                self.kind = "exact"
                self.e164 = e164.value
                self.fixedDigits = nil
                self.wildcardLength = nil
            case .prefix(let prefix):
                self.kind = "prefix"
                self.e164 = nil
                self.fixedDigits = prefix.fixedDigits
                self.wildcardLength = prefix.wildcardLength
            }
        }
    }

    public static let currentFormat = "wildcall-rules-v1"

    public static func build(from rules: [BlockRule], at date: Date) -> RulesExport {
        let userRules = rules.filter { rule in
            if case .user = rule.source { return true } else { return false }
        }
        return RulesExport(
            format: currentFormat,
            exportedAt: date,
            rules: userRules.map { Entry(rule: $0) }
        )
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
