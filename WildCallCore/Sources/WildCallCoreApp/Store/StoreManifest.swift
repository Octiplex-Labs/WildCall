import Foundation

public struct StoreManifest: Codable, Equatable, Sendable {
    public var buildDate: Date
    public var block: BlobInfo
    public var ident: BlobInfo
    public var sources: [String]

    public struct BlobInfo: Codable, Equatable, Sendable {
        public var count: Int
        public var bytes: Int
        public var sha256: String

        public init(count: Int, bytes: Int, sha256: String) {
            self.count = count
            self.bytes = bytes
            self.sha256 = sha256
        }

        public static let empty = BlobInfo(count: 0, bytes: 0, sha256: "")
    }

    public init(buildDate: Date, block: BlobInfo, ident: BlobInfo, sources: [String]) {
        self.buildDate = buildDate
        self.block = block
        self.ident = ident
        self.sources = sources
    }
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
