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
    public let prefixes: [String]

    public init(
        id: String,
        version: String,
        country: String,
        kind: PackKind,
        title: String? = nil,
        license: String? = nil,
        notes: String? = nil,
        prefixes: [String]
    ) {
        self.id = id
        self.version = version
        self.country = country
        self.kind = kind
        self.title = title
        self.license = license
        self.notes = notes
        self.prefixes = prefixes
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
