import Foundation

/// Written by the Call Directory extension into the App Group container on
/// every `beginRequest`, read back by the app to show what iOS actually
/// loaded. This is the only feedback channel from the extension : CallKit
/// gives the app a bare error code, nothing about counts or timing.
public struct ExtensionRunReport: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case running
        case completed
        case failed
    }

    public var startedAt: Date
    public var finishedAt: Date?
    public var isIncremental: Bool
    public var blockNumbers: Int64
    public var identNumbers: Int64
    public var outcome: Outcome
    public var errorDescription: String?

    public init(
        startedAt: Date,
        finishedAt: Date? = nil,
        isIncremental: Bool,
        blockNumbers: Int64 = 0,
        identNumbers: Int64 = 0,
        outcome: Outcome = .running,
        errorDescription: String? = nil
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.isIncremental = isIncremental
        self.blockNumbers = blockNumbers
        self.identNumbers = identNumbers
        self.outcome = outcome
        self.errorDescription = errorDescription
    }

    public var duration: TimeInterval? {
        finishedAt.map { $0.timeIntervalSince(startedAt) }
    }

    public static func load(from url: URL) throws -> ExtensionRunReport? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(ExtensionRunReport.self, from: data)
    }

    public func write(to url: URL) throws {
        let data = try Self.encoder.encode(self)
        try data.write(to: url, options: [.atomic])
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
