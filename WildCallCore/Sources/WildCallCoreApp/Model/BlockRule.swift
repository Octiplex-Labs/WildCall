import Foundation
import WildCallCoreShared

public enum RuleKind: Hashable, Sendable {
    case exact(E164)
    case prefix(E164Prefix)
}

public struct E164Prefix: Hashable, Sendable {
    public let fixedDigits: String
    public let wildcardLength: Int

    public init(fixedDigits: String, wildcardLength: Int) {
        self.fixedDigits = fixedDigits
        self.wildcardLength = wildcardLength
    }
}

public enum RuleSource: Hashable, Sendable {
    case user
    case pack(packId: String)
}

public enum RuleAction: String, Hashable, Sendable, Codable {
    case block
    case identify
}

public struct BlockRule: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let kind: RuleKind
    public let source: RuleSource
    public let action: RuleAction
    public let countryCode: String
    public let label: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: RuleKind,
        source: RuleSource,
        action: RuleAction,
        countryCode: String,
        label: String? = nil,
        createdAt: Date = .init()
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.action = action
        self.countryCode = countryCode
        self.label = label
        self.createdAt = createdAt
    }
}
