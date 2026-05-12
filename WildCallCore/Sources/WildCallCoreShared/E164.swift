import Foundation

public struct E164: Hashable, Sendable, Codable {
    public let value: Int64

    public init?(_ value: Int64) {
        guard value > 0 else { return nil }
        self.value = value
    }
}
