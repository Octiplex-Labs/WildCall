import Foundation
import SwiftData
import WildCallCoreShared

@Model
public final class BlockRuleRecord {
    @Attribute(.unique) public var id: UUID
    public var kindRaw: String
    public var e164Value: Int64?
    public var prefixDigits: String?
    public var prefixWildcardLength: Int?
    public var sourceRaw: String
    public var actionRaw: String
    public var countryCode: String
    public var label: String?
    public var createdAt: Date

    public init(
        id: UUID,
        kindRaw: String,
        e164Value: Int64? = nil,
        prefixDigits: String? = nil,
        prefixWildcardLength: Int? = nil,
        sourceRaw: String,
        actionRaw: String,
        countryCode: String,
        label: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.e164Value = e164Value
        self.prefixDigits = prefixDigits
        self.prefixWildcardLength = prefixWildcardLength
        self.sourceRaw = sourceRaw
        self.actionRaw = actionRaw
        self.countryCode = countryCode
        self.label = label
        self.createdAt = createdAt
    }
}

extension BlockRuleRecord {
    public enum MappingError: Error, Equatable {
        case unknownKind(String)
        case missingExactValue
        case invalidE164(Int64)
        case missingPrefixFields
        case unknownAction(String)
        case malformedSource(String)
    }

    public func toRule() throws -> BlockRule {
        let kind: RuleKind
        switch kindRaw {
        case "exact":
            guard let value = e164Value else { throw MappingError.missingExactValue }
            guard let e164 = E164(value) else { throw MappingError.invalidE164(value) }
            kind = .exact(e164)
        case "prefix":
            guard let digits = prefixDigits, let length = prefixWildcardLength
            else { throw MappingError.missingPrefixFields }
            kind = .prefix(E164Prefix(fixedDigits: digits, wildcardLength: length))
        default:
            throw MappingError.unknownKind(kindRaw)
        }

        let source: RuleSource
        if sourceRaw == "user" {
            source = .user
        } else if sourceRaw.hasPrefix("pack:") {
            source = .pack(packId: String(sourceRaw.dropFirst("pack:".count)))
        } else {
            throw MappingError.malformedSource(sourceRaw)
        }

        guard let action = RuleAction(rawValue: actionRaw) else {
            throw MappingError.unknownAction(actionRaw)
        }

        return BlockRule(
            id: id,
            kind: kind,
            source: source,
            action: action,
            countryCode: countryCode,
            label: label,
            createdAt: createdAt
        )
    }

    public static func from(_ rule: BlockRule) -> BlockRuleRecord {
        let kindRaw: String
        var e164Value: Int64?
        var prefixDigits: String?
        var prefixWildcardLength: Int?
        switch rule.kind {
        case .exact(let e164):
            kindRaw = "exact"
            e164Value = e164.value
        case .prefix(let prefix):
            kindRaw = "prefix"
            prefixDigits = prefix.fixedDigits
            prefixWildcardLength = prefix.wildcardLength
        }

        let sourceRaw: String
        switch rule.source {
        case .user: sourceRaw = "user"
        case .pack(let packId): sourceRaw = "pack:\(packId)"
        }

        return BlockRuleRecord(
            id: rule.id,
            kindRaw: kindRaw,
            e164Value: e164Value,
            prefixDigits: prefixDigits,
            prefixWildcardLength: prefixWildcardLength,
            sourceRaw: sourceRaw,
            actionRaw: rule.action.rawValue,
            countryCode: rule.countryCode,
            label: rule.label,
            createdAt: rule.createdAt
        )
    }
}
