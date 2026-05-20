import Dependencies
import Foundation
import IssueReporting
import WildCallCoreShared

public struct LoadedPack: Equatable, Sendable {
    public let manifest: PackManifest
    public let rules: [BlockRule]

    public init(manifest: PackManifest, rules: [BlockRule]) {
        self.manifest = manifest
        self.rules = rules
    }
}

public enum LoadFromArchiveError: Error, Equatable {
    case archiveRead(PackArchive.ArchiveError)
    case signatureInvalid
    case manifestDecode(String)
}

public struct PackLoader: Sendable {
    public var load: @Sendable (_ manifest: PackManifest, _ now: Date) -> [BlockRule]
    public var loadFromArchive: @Sendable (
        _ archive: Data,
        _ trustedKey: Data,
        _ now: Date
    ) -> Result<LoadedPack, LoadFromArchiveError>

    public init(
        load: @escaping @Sendable (PackManifest, Date) -> [BlockRule],
        loadFromArchive: @escaping @Sendable (Data, Data, Date) -> Result<LoadedPack, LoadFromArchiveError>
    ) {
        self.load = load
        self.loadFromArchive = loadFromArchive
    }
}

extension PackLoader {
    public static let live = PackLoader(
        load: { manifest, now in
            Self.buildRules(manifest: manifest, now: now)
        },
        loadFromArchive: { archiveData, trustedKey, now in
            let archive = PackArchive()
            let contents: PackArchive.Contents
            do {
                contents = try archive.read(archiveData)
            } catch let err as PackArchive.ArchiveError {
                return .failure(.archiveRead(err))
            } catch {
                return .failure(.archiveRead(.decompressionFailed(String(describing: error))))
            }

            let verifier = PackSignatureVerifier.live
            guard verifier.verify(contents.manifest, contents.signature, trustedKey) else {
                return .failure(.signatureInvalid)
            }

            let manifest: PackManifest
            do {
                manifest = try JSONDecoder().decode(PackManifest.self, from: contents.manifest)
            } catch {
                return .failure(.manifestDecode(String(describing: error)))
            }

            let rules = Self.buildRules(manifest: manifest, now: now)
            return .success(LoadedPack(manifest: manifest, rules: rules))
        }
    )

    /// Shared rule-builder used by both `load` (embedded JSON) and
    /// `loadFromArchive` (signed `.wildcallpack`). Quotas are relaxed because
    /// pack patterns are curated and intentionally broader than user input.
    static func buildRules(manifest: PackManifest, now: Date) -> [BlockRule] {
        @Dependency(\.wildcardParser) var parser
        @Dependency(\.uuid) var uuid

        let packQuotas = WildcardQuotas(
            perPattern: .max,
            totalUser: .max,
            minFixedDigits: 1
        )

        return withDependencies {
            $0.wildcardQuotas = packQuotas
        } operation: {
            var rules: [BlockRule] = []
            rules.reserveCapacity(manifest.prefixes.count)
            for pattern in manifest.prefixes {
                switch parser.parse(pattern, manifest.country) {
                case .success(let prefix):
                    rules.append(
                        BlockRule(
                            id: uuid(),
                            kind: .prefix(prefix),
                            source: .pack(packId: manifest.id),
                            action: .block,
                            countryCode: manifest.country,
                            label: nil,
                            createdAt: now
                        )
                    )
                case .failure(let error):
                    reportIssue("Pack \(manifest.id): skipped malformed pattern '\(pattern)' (\(error))")
                }
            }
            return rules
        }
    }
}

extension PackLoader: DependencyKey {
    public static let liveValue: PackLoader = .live
    public static let testValue: PackLoader = PackLoader(
        load: { _, _ in unimplemented("PackLoader.load", placeholder: []) },
        loadFromArchive: { _, _, _ in
            unimplemented(
                "PackLoader.loadFromArchive",
                placeholder: .failure(.signatureInvalid)
            )
        }
    )
}

extension DependencyValues {
    public var packLoader: PackLoader {
        get { self[PackLoader.self] }
        set { self[PackLoader.self] = newValue }
    }
}
