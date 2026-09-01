import Foundation

/// On-disk JSON shape for a pack manifest (v1, embedded or remote).
/// Signed payloads (Phase 4) wrap this struct with a detached Ed25519
/// signature; for embedded packs we trust the .app bundle's code signing.
public struct PackManifest: Codable, Hashable, Sendable {
    public let id: String
    public let version: String
    public let country: String
    public let kind: PackKind
    public let title: String?
    public let license: String?
    public let notes: String?
    /// 64-hex (32-byte) Ed25519 public key the publisher claims to own.
    /// Required for third-party packs (TOFU pinning anchor). Octiplex packs
    /// omit this : trust is rooted in OctiplexTrust.publicKey embedded in
    /// the app.
    public let publisherKey: String?
    /// Ids of packs this one replaces. Installing it removes them (rules
    /// included) so the user does not end up with two overlapping packs.
    public let supersedes: [String]?
    public let prefixes: [String]

    public init(
        id: String,
        version: String,
        country: String,
        kind: PackKind,
        title: String? = nil,
        license: String? = nil,
        notes: String? = nil,
        publisherKey: String? = nil,
        supersedes: [String]? = nil,
        prefixes: [String]
    ) {
        self.id = id
        self.version = version
        self.country = country
        self.kind = kind
        self.title = title
        self.license = license
        self.notes = notes
        self.publisherKey = publisherKey
        self.supersedes = supersedes
        self.prefixes = prefixes
    }
}

extension PackManifest {
    /// Decode the publisher's claimed public key into raw bytes. Returns nil
    /// when the manifest omits the field or the hex is malformed/wrong length.
    public func publisherKeyBytes() -> Data? {
        guard let hex = publisherKey,
              let bytes = Data(hex: hex),
              bytes.count == 32
        else { return nil }
        return bytes
    }
}

extension Data {
    init?(hex: String) {
        let cleaned = hex.lowercased().filter { "0123456789abcdef".contains($0) }
        guard cleaned.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}

extension PackManifest {
    public enum LoadError: Error, Equatable {
        case fileMissing(URL)
        case decodingFailed(String)
    }

    public static func load(from url: URL) throws -> PackManifest {
        guard FileManager.default.fileExists(atPath: url.path()) else {
            throw LoadError.fileMissing(url)
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PackManifest.self, from: data)
        } catch {
            throw LoadError.decodingFailed(String(describing: error))
        }
    }
}
