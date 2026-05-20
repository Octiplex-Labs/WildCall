import Foundation
import SWCompression

/// In-memory read/write of `.wildcallpack` files (tarball gzip).
///
/// Layout inside the tarball:
///   `manifest.json` — UTF-8 JSON, the canonical bytes signed by the publisher.
///   `manifest.sig`  — raw 64-byte Ed25519 signature over the manifest bytes.
///   `payload.bin`   — optional binary payload (Int64 LE, sorted) for
///                     kind=preExpanded packs. Absent for kind=prefixes.
public struct PackArchive: Sendable {
    public struct Contents: Equatable, Sendable {
        public let manifest: Data
        public let signature: Data
        public let payload: Data?

        public init(manifest: Data, signature: Data, payload: Data? = nil) {
            self.manifest = manifest
            self.signature = signature
            self.payload = payload
        }
    }

    public enum ArchiveError: Error, Equatable {
        case decompressionFailed(String)
        case tarParseFailed(String)
        case missingEntry(String)
        case tarBuildFailed(String)
        case gzipBuildFailed(String)
    }

    public static let manifestName = "manifest.json"
    public static let signatureName = "manifest.sig"
    public static let payloadName = "payload.bin"

    public init() {}

    public func read(_ data: Data) throws -> Contents {
        let tarData: Data
        do {
            tarData = try GzipArchive.unarchive(archive: data)
        } catch {
            throw ArchiveError.decompressionFailed(String(describing: error))
        }

        let entries: [TarEntry]
        do {
            entries = try TarContainer.open(container: tarData)
        } catch {
            throw ArchiveError.tarParseFailed(String(describing: error))
        }

        guard let manifestEntry = entries.first(where: { $0.info.name == Self.manifestName }),
              let manifestData = manifestEntry.data
        else { throw ArchiveError.missingEntry(Self.manifestName) }

        guard let signatureEntry = entries.first(where: { $0.info.name == Self.signatureName }),
              let signatureData = signatureEntry.data
        else { throw ArchiveError.missingEntry(Self.signatureName) }

        let payloadData = entries
            .first(where: { $0.info.name == Self.payloadName })?
            .data

        return Contents(manifest: manifestData, signature: signatureData, payload: payloadData)
    }

    public func write(_ contents: Contents) throws -> Data {
        var entries: [TarEntry] = []
        entries.append(makeEntry(name: Self.manifestName, data: contents.manifest))
        entries.append(makeEntry(name: Self.signatureName, data: contents.signature))
        if let payload = contents.payload {
            entries.append(makeEntry(name: Self.payloadName, data: payload))
        }

        let tarData = TarContainer.create(from: entries)
        do {
            return try GzipArchive.archive(data: tarData)
        } catch {
            throw ArchiveError.gzipBuildFailed(String(describing: error))
        }
    }

    private func makeEntry(name: String, data: Data) -> TarEntry {
        var info = TarEntryInfo(name: name, type: .regular)
        info.permissions = Permissions(rawValue: 0o644)
        return TarEntry(info: info, data: data)
    }
}
