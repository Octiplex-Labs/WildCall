import Dependencies
import Foundation
import IssueReporting

/// Discovers the `*.source.json` manifests bundled in the app. Adding a
/// country is a matter of dropping a new file in `Packs/` : no code change.
public struct EmbeddedPacks: Sendable {
    public var manifests: @Sendable () -> [PackManifest]

    public init(manifests: @escaping @Sendable () -> [PackManifest]) {
        self.manifests = manifests
    }
}

extension EmbeddedPacks {
    public static func live(bundle: Bundle = .main) -> EmbeddedPacks {
        EmbeddedPacks {
            let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
                .filter { $0.lastPathComponent.hasSuffix(".source.json") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if urls.isEmpty {
                reportIssue("No embedded *.source.json packs found in bundle")
            }
            return urls.compactMap { url in
                do {
                    return try PackManifest.load(from: url)
                } catch {
                    reportIssue("Embedded pack \(url.lastPathComponent) failed to decode: \(error)")
                    return nil
                }
            }
        }
    }
}

extension EmbeddedPacks: DependencyKey {
    public static let liveValue: EmbeddedPacks = .live()
    public static let testValue: EmbeddedPacks = EmbeddedPacks {
        unimplemented("EmbeddedPacks.manifests", placeholder: [])
    }
}

extension DependencyValues {
    public var embeddedPacks: EmbeddedPacks {
        get { self[EmbeddedPacks.self] }
        set { self[EmbeddedPacks.self] = newValue }
    }
}
