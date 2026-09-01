import Foundation
import WildCallCoreShared

public struct StoreManifest: Codable, Equatable, Sendable {
    public static let currentFormatVersion = Int(BlockStoreFormat.version)

    public var formatVersion: Int
    public var buildDate: Date
    public var block: BlobInfo
    public var ident: BlobInfo
    public var sources: [String]
    /// Outcome of the last `reloadExtension` for this build, nil while the
    /// reload is still running or never happened.
    public var lastReload: ReloadRecord?

    public struct BlobInfo: Codable, Equatable, Sendable {
        public var count: Int
        public var ranges: Int
        public var bytes: Int
        public var sha256: String

        public init(count: Int, ranges: Int? = nil, bytes: Int, sha256: String) {
            self.count = count
            self.ranges = ranges ?? count
            self.bytes = bytes
            self.sha256 = sha256
        }

        public static let empty = BlobInfo(count: 0, ranges: 0, bytes: 0, sha256: "")

        enum CodingKeys: String, CodingKey { case count, ranges, bytes, sha256 }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let count = try container.decode(Int.self, forKey: .count)
            self.count = count
            self.ranges = try container.decodeIfPresent(Int.self, forKey: .ranges) ?? count
            self.bytes = try container.decode(Int.self, forKey: .bytes)
            self.sha256 = try container.decode(String.self, forKey: .sha256)
        }
    }

    public struct ReloadRecord: Codable, Equatable, Sendable {
        public var date: Date
        public var succeeded: Bool
        public var failure: ReloadFailure?

        public init(date: Date, succeeded: Bool, failure: ReloadFailure? = nil) {
            self.date = date
            self.succeeded = succeeded
            self.failure = failure
        }
    }

    public init(
        formatVersion: Int = StoreManifest.currentFormatVersion,
        buildDate: Date,
        block: BlobInfo,
        ident: BlobInfo,
        sources: [String],
        lastReload: ReloadRecord? = nil
    ) {
        self.formatVersion = formatVersion
        self.buildDate = buildDate
        self.block = block
        self.ident = ident
        self.sources = sources
        self.lastReload = lastReload
    }

    enum CodingKeys: String, CodingKey { case formatVersion, buildDate, block, ident, sources, lastReload }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Manifests written before the range format carried no version.
        self.formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        self.buildDate = try container.decode(Date.self, forKey: .buildDate)
        self.block = try container.decode(BlobInfo.self, forKey: .block)
        self.ident = try container.decode(BlobInfo.self, forKey: .ident)
        self.sources = try container.decode([String].self, forKey: .sources)
        self.lastReload = try container.decodeIfPresent(ReloadRecord.self, forKey: .lastReload)
    }

    public var totalNumbers: Int { block.count + ident.count }
}

extension StoreManifest {
    public static func load(from url: URL) throws -> StoreManifest? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.iso8601.decode(StoreManifest.self, from: data)
    }

    public func write(to url: URL) throws {
        let data = try JSONEncoder.iso8601Pretty.encode(self)
        try writeAtomically(data, to: url)
    }
}

extension JSONDecoder {
    fileprivate static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    fileprivate static let iso8601Pretty: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
