import Dependencies
import Foundation
import IssueReporting
import WildCallCoreShared

public struct PackLoader: Sendable {
    public var load: @Sendable (_ manifest: PackManifest, _ now: Date) -> [BlockRule]

    public init(load: @escaping @Sendable (PackManifest, Date) -> [BlockRule]) {
        self.load = load
    }
}

extension PackLoader {
    public static let live = PackLoader { manifest, now in
        @Dependency(\.wildcardParser) var parser
        @Dependency(\.uuid) var uuid

        // Pack patterns are curated and intentionally broader than what a
        // user can author (e.g. 3 fixed national digits = 10⁶ entries).
        // Relax the parser quotas inside this loader only.
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
    public static let testValue: PackLoader = PackLoader { _, _ in
        unimplemented("PackLoader.load", placeholder: [])
    }
}

extension DependencyValues {
    public var packLoader: PackLoader {
        get { self[PackLoader.self] }
        set { self[PackLoader.self] = newValue }
    }
}
